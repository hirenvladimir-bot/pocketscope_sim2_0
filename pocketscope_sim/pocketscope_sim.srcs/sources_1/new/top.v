`timescale 1ns / 1ps
//=============================================================================
// PocketScope - Multi-function Pocket Instrument
// EGO1 (XC7A35T-1CSG324C) Top Module
//=============================================================================
// Modes: 00=Signal Gen, 01=Oscilloscope, 10=Lissajous, 11=Kaleidoscope
//=============================================================================

module top
(
    input  wire          sys_clk,       // 100MHz system clock (matches EGO1.xdc)
    input  wire          rst_n,
    output wire [3:0]    vga_r, vga_g, vga_b,
    output wire          hsync, vsync,
    // DAC0832
    output wire [7:0]    dac_d,
    output wire          dac_ile, dac_cs_n, dac_wr1_n, dac_wr2_n, dac_xfer_n,
    // XADC analog inputs
    input  wire          adc_p_in, adc_n_in,
    input  wire          adc_vauxp0, adc_vauxn0, // ADC_MUX_OUT J5 pins 13-14 (VAUXP[0]/N[0])
    // UI
    input  wire [4:0]    btn,
    input  wire [7:0]    sw_in,
    input  wire [7:0]    sw_dip,
    // Status / loopback
    output wire [2:0]    led_speed,
    output wire [3:0]    loop_tx,       // loop_tx[0] repurposed as mux_sel
    input  wire [3:0]    loop_rx,
    // 4053 analog switch control (expansion board)
    output wire          mux_sel        // 0=CH1, 1=CH2
);

//=============================================================================
// Clock generation: 100MHz -> 25MHz
//=============================================================================
wire clk_25m;

clk_div_25m u_clk_div (
    .clk_100m(sys_clk),
    .rst_n(rst_n),
    .clk_25m(clk_25m)
);

// Debug
wire dbg_clk25m = clk_25m;

//=============================================================================
// UI Controller
//=============================================================================
wire [1:0] device_mode;
wire [2:0] sig_gen_submode;
wire [1:0] mod_type;
wire       mod_enable;
wire [23:0] frequency_ftw;
wire [7:0]  amplitude;
wire [7:0]  mod_depth;
wire [2:0]  scope_timebase;
wire [7:0]  scope_trigger_level;

ui_ctrl #(.PHASE_WIDTH(24)) u_ui (
    .clk(clk_25m), .rst_n(rst_n),
    .btn(btn), .sw(sw_in), .sw_dip(sw_dip),
    .device_mode(device_mode), .sig_gen_submode(sig_gen_submode),
    .mod_type(mod_type), .mod_enable(mod_enable),
    .frequency_ftw(frequency_ftw), .amplitude(amplitude), .mod_depth(mod_depth),
    .scope_timebase(scope_timebase), .scope_trigger_level(scope_trigger_level)
);

// Debug
wire [23:0] dbg_freq_ftw  = frequency_ftw;
wire [7:0]  dbg_amplitude = amplitude;

//=============================================================================
// DDS Signal Generator
//=============================================================================
wire [1:0] dds_wave_type;
assign dds_wave_type = sig_gen_submode[2] ? 2'b00 : sig_gen_submode[1:0];

wire [7:0]  dds_wave_out;
wire [23:0] dds_ftw_in;
wire [9:0]  dds_y;

// Modulation
wire [23:0] fm_ftw;
wire [7:0]  mod_signal_out;

modulation #(.PHASE_WIDTH(24)) u_mod (
    .clk(clk_25m), .rst_n(rst_n),
    .mod_type(mod_type),
    .mod_enable(mod_enable && (device_mode == 2'b00)),
    .base_ftw(frequency_ftw),
    .carrier_in(dds_wave_out),
    .mod_depth(mod_depth),
    .fm_ftw_out(fm_ftw),
    .signal_out(mod_signal_out)
);

assign dds_ftw_in = (mod_enable && mod_type == 2'b01) ? fm_ftw : frequency_ftw;

dds_core #(.PHASE_WIDTH(24), .LUT_ADDR_W(10), .LUT_DATA_W(8)) u_dds (
    .clk(clk_25m), .rst_n(rst_n),
    .ftw(dds_ftw_in), .wave_type(dds_wave_type),
    .wave_out(dds_wave_out)
);

// Debug
wire [7:0] dbg_dds_out   = dds_wave_out;
wire [7:0] dbg_mod_signal = mod_signal_out;

//=============================================================================
// DAC Output — Bipolar ±3.3V with RMS Amplitude Control (0–2Vrms)
//=============================================================================
// DAC0832 bipolar configuration: Vout = Vref * (D - 128) / 128
// EGO1 Vref = 3.3V (measured), full-scale output = ±3.3V (6.6Vpp).
// Digital compensation maps amplitude=255 → 2Vrms (2.828V peak for sine):
//   AMPL_CAL = round(256 * 2.90V / 3.30V) ≈ 225
//   (2.90V > 2.828V compensates for integer truncation, ensuring ≥2Vrms)
//   0x80 = 0V; amplitude=255 → ampl_eff≈223 → DAC output≈±2.83V peak
// Actual Vrms depends on waveform:
//   Sine:     max ≈ 2.00Vrms (≥ 2Vrms requirement met)
//   Square:   max ≈ 2.83Vrms (≥ 2Vrms)
//   Triangle: max ≈ 1.64Vrms (physical limit: Vrms = Vpeak/√3)

localparam DAC_VREF_MV = 3300;   // DAC reference voltage (mV, measured)
localparam DAC_VOUT_MV = 2900;   // Target peak mV (slightly > 2828 for truncation)
localparam AMPL_CAL    = (DAC_VOUT_MV * 256) / DAC_VREF_MV;  // ≈ 225

// Scale UI amplitude (0-255) by compensation factor
wire [15:0] ampl_scaled = amplitude * AMPL_CAL;
wire [7:0]  ampl_eff    = ampl_scaled[15:8];   // effective amplitude: 0 ~ 224

// Select signal source: DDS direct or modulated
wire [7:0] dac_data_raw;
assign dac_data_raw = mod_enable ? mod_signal_out : dds_wave_out;

// Bipolar amplitude scaling with saturation (prevents wraparound distortion)
// dac_data_in = saturate(128 + (dac_data_raw - 128) * ampl_eff / 256, 0, 255)
wire signed [8:0]  dac_dev   = $signed({1'b0, dac_data_raw}) - 9'sd128;
wire signed [17:0] dac_prod  = dac_dev * $signed({1'b0, ampl_eff});
wire signed [9:0]  dac_sum   = $signed({dac_prod[16], dac_prod[16:8]}) + 10'sd128;
wire [7:0]         dac_data_in = dac_sum[9] ? 8'd0 :        // negative → clamp to 0
                                  dac_sum[8] ? 8'd255 :       // >255 → clamp to 255
                                               dac_sum[7:0]; // 0–255 pass through

wire dac_update;

// DDS Y for sig-gen preview
assign dds_y = 10'd479 - (({2'b0, dds_wave_out} * 10'd479) >> 8);

// DAC update rate divider (25MHz / 64 ≈ 390kHz)
reg [5:0]  dac_rate_cnt;
reg        dac_update_trig;

always @(posedge clk_25m or negedge rst_n) begin
    if (!rst_n) begin
        dac_rate_cnt <= 0;
        dac_update_trig <= 0;
    end else begin
        dac_update_trig <= 0;
        if (dac_rate_cnt == 63) begin
            dac_rate_cnt <= 0;
            dac_update_trig <= 1;
        end else begin
            dac_rate_cnt <= dac_rate_cnt + 1'b1;
        end
    end
end

assign dac_update = dac_update_trig && (device_mode == 2'b00);

dac0832_ctrl u_dac (
    .clk(clk_25m), .rst_n(rst_n),
    .dac_data_in(dac_data_in), .dac_update(dac_update),
    .dac_d(dac_d), .dac_ile(dac_ile), .dac_cs_n(dac_cs_n),
    .dac_wr1_n(dac_wr1_n), .dac_wr2_n(dac_wr2_n), .dac_xfer_n(dac_xfer_n)
);

//=============================================================================
// XADC Dual-Channel Reader
//=============================================================================
// Pre-declare sample rate wires (before xadc_reader instantiation to avoid
// implicit wire declaration warnings).
wire [15:0] sample_rate_hz_sys;
wire        sample_rate_update_sys;

// Map physical ADC inputs to XADC VAUXP/VAUXN buses
wire [15:0] xadc_vauxp, xadc_vauxn;
// VAUXP/VAUXN bus mapping to XADC auxiliary channels:
//   [15:4] = unused
//   [3]    = 0 (VAUXP[3]/VAUXN[3] unused — USE_4053=1, only VAUXP[0] needed)
//   [2]    = unused
//   [1]    = unused
//   [0]    = adc_vauxp0/vauxn0  (AD0, auxiliary channel 0, DRP addr 0x10 — ADC_MUX_OUT)
assign xadc_vauxp = {12'd0, 1'b0, 3'b0, adc_vauxp0};
assign xadc_vauxn = {12'd0, 1'b0, 3'b0, adc_vauxn0};

wire [11:0] adc_ch1_raw, adc_ch2_raw;
wire        adc_ch1_vld, adc_ch2_vld;

xadc_reader #(
    .SIM_MODE(0),
    .USE_4053(1),           // 1 = single XADC channel + 4053 mux
    .SINGLE_CH_ADDR(7'h10), // VAUXP[0]/VAUXN[0] (AD0, J5 pins 13-14) carries the muxed signal
    .SETTLE_CYCLES(10)      // 100ns settle time at 100MHz (> 74HC4053 t_on=60ns)
) u_xadc (
    .clk(sys_clk), .rst_n(rst_n),
    .vp_in(adc_p_in), .vn_in(adc_n_in),
    .vauxp(xadc_vauxp), .vauxn(xadc_vauxn),
    .ch1_data(adc_ch1_raw), .ch1_valid(adc_ch1_vld),
    .ch2_data(adc_ch2_raw), .ch2_valid(adc_ch2_vld),
    .mux_sel(mux_sel),
    .sample_rate_hz(sample_rate_hz_sys),
    .sample_rate_update(sample_rate_update_sys)
);

//=============================================================================
// CDC Bridge: 100MHz (sys_clk) → 25MHz (clk_25m)
// XADC valid pulses are 1 cycle wide at 100MHz (10ns) — too narrow for
// 25MHz logic (40ns period). Pulse stretching in the source domain +
// 2-stage synchronizer in the destination domain ensures safe capture.
// Sample rate ~403kSPS per ch → one sample every ~62 clk_25m cycles → safe.
//=============================================================================

// --- 100MHz domain: pulse stretching + data hold ---
reg [3:0]  ch1_stretch_cnt, ch2_stretch_cnt;
reg        ch1_valid_sys, ch2_valid_sys;
reg [11:0] ch1_data_sys, ch2_data_sys;

always @(posedge sys_clk or negedge rst_n) begin
    if (!rst_n) begin
        ch1_stretch_cnt <= 0;
        ch2_stretch_cnt <= 0;
        ch1_valid_sys   <= 0;
        ch2_valid_sys   <= 0;
        ch1_data_sys    <= 12'h800;
        ch2_data_sys    <= 12'h800;
    end else begin
        // CH1: stretch valid pulse to 8 sys_clk cycles (80ns > 40ns clk_25m period)
        if (adc_ch1_vld) begin
            ch1_valid_sys   <= 1'b1;
            ch1_stretch_cnt <= 0;
            ch1_data_sys    <= adc_ch1_raw;
        end else if (ch1_valid_sys) begin
            if (ch1_stretch_cnt == 4'd7) begin
                ch1_valid_sys   <= 1'b0;
                ch1_stretch_cnt <= 0;
            end else begin
                ch1_stretch_cnt <= ch1_stretch_cnt + 1'b1;
            end
        end

        // CH2: same stretching logic
        if (adc_ch2_vld) begin
            ch2_valid_sys   <= 1'b1;
            ch2_stretch_cnt <= 0;
            ch2_data_sys    <= adc_ch2_raw;
        end else if (ch2_valid_sys) begin
            if (ch2_stretch_cnt == 4'd7) begin
                ch2_valid_sys   <= 1'b0;
                ch2_stretch_cnt <= 0;
            end else begin
                ch2_stretch_cnt <= ch2_stretch_cnt + 1'b1;
            end
        end
    end
end

// --- 25MHz domain: 2-stage sync + edge detect + data capture ---
reg        ch1_v_s25_1, ch1_v_s25_2, ch1_v_s25_prev;
reg [11:0] adc_ch1_synced;
reg        ch2_v_s25_1, ch2_v_s25_2, ch2_v_s25_prev;
reg [11:0] adc_ch2_synced;

always @(posedge clk_25m or negedge rst_n) begin
    if (!rst_n) begin
        ch1_v_s25_1    <= 0;
        ch1_v_s25_2    <= 0;
        ch1_v_s25_prev <= 0;
        adc_ch1_synced <= 12'h800;
        ch2_v_s25_1    <= 0;
        ch2_v_s25_2    <= 0;
        ch2_v_s25_prev <= 0;
        adc_ch2_synced <= 12'h800;
    end else begin
        // 2-stage synchronizer
        ch1_v_s25_1 <= ch1_valid_sys;
        ch1_v_s25_2 <= ch1_v_s25_1;
        ch1_v_s25_prev <= ch1_v_s25_2;

        ch2_v_s25_1 <= ch2_valid_sys;
        ch2_v_s25_2 <= ch2_v_s25_1;
        ch2_v_s25_prev <= ch2_v_s25_2;

        // Rising-edge detect + data capture
        if (ch1_v_s25_2 && !ch1_v_s25_prev)
            adc_ch1_synced <= ch1_data_sys;
        if (ch2_v_s25_2 && !ch2_v_s25_prev)
            adc_ch2_synced <= ch2_data_sys;
    end
end

// Synchronized valid flags and 8-bit data in 25MHz domain
wire adc_ch1_vld_25m = ch1_v_s25_2 && !ch1_v_s25_prev;
wire adc_ch2_vld_25m = ch2_v_s25_2 && !ch2_v_s25_prev;
wire [7:0] adc_ch1_8b = adc_ch1_synced[11:4];
wire [7:0] adc_ch2_8b = adc_ch2_synced[11:4];

//=============================================================================
// CDC: Sample rate from 100MHz sys_clk domain to 25MHz clk_25m domain
// Data updates once per second, stretched update flag ensures safe capture.
//=============================================================================

// 2-stage synchronizer for update flag (100MHz -> 25MHz)
reg sample_rate_update_sync1, sample_rate_update_sync2, sample_rate_update_prev;
// Captured sample rate in 25MHz domain
reg [15:0] sample_rate_disp;

always @(posedge clk_25m or negedge rst_n) begin
    if (!rst_n) begin
        sample_rate_update_sync1 <= 1'b0;
        sample_rate_update_sync2 <= 1'b0;
        sample_rate_update_prev  <= 1'b0;
        sample_rate_disp         <= 16'd0;
    end else begin
        // Synchronize update flag
        sample_rate_update_sync1 <= sample_rate_update_sys;
        sample_rate_update_sync2 <= sample_rate_update_sync1;
        sample_rate_update_prev  <= sample_rate_update_sync2;
        // Capture data on rising edge of synchronized update
        if (sample_rate_update_sync2 && !sample_rate_update_prev) begin
            sample_rate_disp <= sample_rate_hz_sys;
        end
    end
end

//=============================================================================
// Oscilloscope Trigger
// Rising-edge trigger on CH1: when adc_ch1_8b crosses above
// scope_trigger_level, the trigger fires and resets the write address
// to align the trigger event with the screen center.
//=============================================================================
reg        trigger_armed;
reg [7:0]  ch1_prev;
reg [15:0] trigger_holdoff_cnt;   // hold-off counter (~10ms at 25MHz = 250000)
wire       trigger_event;
reg        trigger_fired;

localparam TRIGGER_HOLDOFF = 16'd50000;  // ~2ms hold-off at 25MHz

always @(posedge clk_25m or negedge rst_n) begin
    if (!rst_n) begin
        trigger_armed      <= 1'b0;
        ch1_prev           <= 8'd128;
        trigger_holdoff_cnt <= 0;
        trigger_fired      <= 1'b0;
    end else begin
        trigger_fired <= 1'b0;

        // Track previous CH1 value for edge detection
        if (adc_ch1_vld_25m)
            ch1_prev <= adc_ch1_8b;

        // Hold-off countdown
        if (trigger_holdoff_cnt > 0)
            trigger_holdoff_cnt <= trigger_holdoff_cnt - 1'b1;

        // Trigger FSM
        if (device_mode == 2'b01) begin  // scope mode only
            if (!trigger_armed) begin
                // Arm when signal goes below trigger level (wait for rising edge)
                if (adc_ch1_vld_25m && adc_ch1_8b < scope_trigger_level)
                    trigger_armed <= 1'b1;
            end else begin
                // Fire on rising edge crossing + hold-off expired
                if (adc_ch1_vld_25m &&
                    ch1_prev < scope_trigger_level &&
                    adc_ch1_8b >= scope_trigger_level &&
                    trigger_holdoff_cnt == 0) begin
                    trigger_fired      <= 1'b1;
                    trigger_armed      <= 1'b0;
                    trigger_holdoff_cnt <= TRIGGER_HOLDOFF;
                end
            end
        end else begin
            trigger_armed <= 1'b0;
        end
    end
end

assign trigger_event = trigger_fired;

//=============================================================================
// Waveform Storage (Dual Channel RAM)
//=============================================================================
wire [9:0] wr_addr;
wire [9:0] scroll_shift;
wire       de;
wire [9:0] pixel_x, pixel_y;

// Trigger resets the write address to align trigger point with screen center
// (center = 512 pixels into the 1024-sample buffer)
wire trigger_reset;
assign trigger_reset = trigger_event && (device_mode == 2'b01);

scroll_addr_gen u_scroll (
    .clk(clk_25m), .rst_n(rst_n),
    .pixel_x(pixel_x),
    .trigger_reset(trigger_reset),
    .display_addr(wr_addr),
    .shift(scroll_shift)
);

wire [7:0] wave_ch1, wave_ch2;
wire [9:0] display_addr = wr_addr;

wave_ram_ch1 u_ram_ch1 (
    .clk(clk_25m),
    .we(adc_ch1_vld_25m), .wr_addr(wr_addr), .din(adc_ch1_8b),
    .rd_addr(display_addr), .dout(wave_ch1)
);

wave_ram_ch2 u_ram_ch2 (
    .clk(clk_25m),
    .we(adc_ch2_vld_25m), .wr_addr(wr_addr), .din(adc_ch2_8b),
    .rd_addr(display_addr), .dout(wave_ch2)
);

//=============================================================================
// VGA Controller
//=============================================================================
vga_ctrl u_vga (
    .clk(clk_25m), .rst_n(rst_n),
    .hsync(hsync), .vsync(vsync),
    .de(de), .pixel_x(pixel_x), .pixel_y(pixel_y)
);

//=============================================================================
// Waveform Analyzers (Frequency, Vpp, Type, RMS, Avg, Max)
//
// Calibration based on EGO1_Oscilloscope_Gen extension board:
//   Signal chain: BNC → 10kΩ + 100kΩ trimmer → MCP6002 (G=1.1×) → 74HC4053 → XADC VAUXP0 (J5 pin 13)
//   XADC: 12-bit 0-1V, code uses adc[11:4] (8-bit, 0-255)
//   ADC LSB (8-bit) = 1V/256 = 3.90625mV at XADC input
//   Front-end gain at max trimmer: 100k/(10k+100k) × 1.1 ≈ 1.0
//   → BNC mV ≈ ADC_count × 3.906 → CAL_MV_X1024 = round(3.90625×1024) = 4000
//
// Frequency calibration (4053 mux mode, ~403kSPS per ch):
//   GATE_MAX = 10000 samples, sample_rate ≈ 403000 SPS
//   Gate time = 10000/403000 ≈ 24.8ms
//   FREQ_CAL_X10 = sample_rate × 10 / GATE_MAX = 403 (for 403kSPS)
//   → freq_hz = zc_count × 403 / 10
//   For simulation: sample_rate ≈ 100000 → FREQ_CAL_X10 = 100
//=============================================================================
localparam FREQ_CAL_X10_CH = 403;   // frequency cal (×10): 403 for 403kSPS
localparam CAL_MV_X1024_VAL = 4000; // mV cal (×1024): 4000 → 3.90625 mV/LSB

wire [15:0] freq_ch1, freq_ch2;
wire [7:0]  vpp_ch1, vpp_ch2;
wire [1:0]  type_ch1, type_ch2;
wire        meas_valid_ch1, meas_valid_ch2;
wire [7:0]  rms_ch1, rms_ch2;
wire [7:0]  avg_ch1, avg_ch2;
wire [7:0]  max_ch1, max_ch2;
wire [15:0] vpp_mv_ch1, vpp_mv_ch2;
wire [15:0] rms_mv_ch1, rms_mv_ch2;
wire [15:0] avg_mv_ch1, avg_mv_ch2;
wire [15:0] max_mv_ch1, max_mv_ch2;

wave_analyzer #(
    .FREQ_CAL_X10(FREQ_CAL_X10_CH),
    .CAL_MV_X1024(CAL_MV_X1024_VAL)
) u_analyzer_ch1 (
    .clk(clk_25m), .rst_n(rst_n),
    .wave_data(adc_ch1_8b), .wave_valid(adc_ch1_vld_25m),
    .frequency_hz(freq_ch1), .vpp(vpp_ch1),
    .wave_type_det(type_ch1), .meas_valid(meas_valid_ch1),
    .rms(rms_ch1), .avg_val(avg_ch1), .max_val(max_ch1),
    .vpp_mv(vpp_mv_ch1), .rms_mv(rms_mv_ch1),
    .avg_mv(avg_mv_ch1), .max_mv(max_mv_ch1)
);

wave_analyzer #(
    .FREQ_CAL_X10(FREQ_CAL_X10_CH),
    .CAL_MV_X1024(CAL_MV_X1024_VAL)
) u_analyzer_ch2 (
    .clk(clk_25m), .rst_n(rst_n),
    .wave_data(adc_ch2_8b), .wave_valid(adc_ch2_vld_25m),
    .frequency_hz(freq_ch2), .vpp(vpp_ch2),
    .wave_type_det(type_ch2), .meas_valid(meas_valid_ch2),
    .rms(rms_ch2), .avg_val(avg_ch2), .max_val(max_ch2),
    .vpp_mv(vpp_mv_ch2), .rms_mv(rms_mv_ch2),
    .avg_mv(avg_mv_ch2), .max_mv(max_mv_ch2)
);

//=============================================================================
// Display Modules
//=============================================================================

// 1) Oscilloscope mode (dual-channel waveform display)
wire [3:0] scope_r, scope_g, scope_b;

waveform_display u_scope_display (
    .clk(clk_25m), .de(de),
    .pixel_x(pixel_x), .pixel_y(pixel_y),
    .wave_ch1(wave_ch1), .wave_ch2(wave_ch2),
    .freq_ch1(freq_ch1), .vpp_ch1(vpp_ch1), .type_ch1(type_ch1),
    .freq_ch2(freq_ch2), .vpp_ch2(vpp_ch2), .type_ch2(type_ch2),
    .meas_valid(meas_valid_ch1),
    .rms_ch1(rms_ch1), .avg_ch1(avg_ch1), .max_ch1(max_ch1),
    .rms_ch2(rms_ch2), .avg_ch2(avg_ch2), .max_ch2(max_ch2),
    .vpp_mv_ch1(vpp_mv_ch1), .rms_mv_ch1(rms_mv_ch1),
    .avg_mv_ch1(avg_mv_ch1), .max_mv_ch1(max_mv_ch1),
    .vpp_mv_ch2(vpp_mv_ch2), .rms_mv_ch2(rms_mv_ch2),
    .avg_mv_ch2(avg_mv_ch2), .max_mv_ch2(max_mv_ch2),
    .sample_rate_hz(sample_rate_disp),
    .trigger_armed(trigger_armed),
    .trigger_level(scope_trigger_level),
    .vga_r(scope_r), .vga_g(scope_g), .vga_b(scope_b)
);

// 2) Lissajous X-Y mode
wire [3:0] liss_r, liss_g, liss_b;

lissajous_display u_liss (
    .clk(clk_25m), .rst_n(rst_n), .de(de),
    .pixel_x(pixel_x), .pixel_y(pixel_y),
    .ch1_data(adc_ch1_8b), .ch2_data(adc_ch2_8b),
    .ch1_valid(adc_ch1_vld_25m), .ch2_valid(adc_ch2_vld_25m),
    .vga_r(liss_r), .vga_g(liss_g), .vga_b(liss_b)
);

// 3) Kaleidoscope mode
wire [3:0] kalei_r, kalei_g, kalei_b;

kaleidoscope u_kalei (
    .clk(clk_25m), .rst_n(rst_n), .de(de),
    .pixel_x(pixel_x), .pixel_y(pixel_y),
    .ch1_data(adc_ch1_8b), .ch2_data(adc_ch2_8b),
    .ch1_valid(adc_ch1_vld_25m), .ch2_valid(adc_ch2_vld_25m),
    .vga_r(kalei_r), .vga_g(kalei_g), .vga_b(kalei_b)
);

// 4) Signal Generator preview (simple inline display)
reg [3:0] sggen_r, sggen_g, sggen_b;

always @(*) begin
    if (de) begin
        // Grid
        if ((pixel_x % 80) == 0 || (pixel_y % 60) == 0) begin
            sggen_r = 4'h2; sggen_g = 4'h2; sggen_b = 4'h2;
        end
        // Center cross
        else if (pixel_x == 320 || pixel_y == 240) begin
            sggen_r = 4'h4; sggen_g = 4'h4; sggen_b = 4'h4;
        end
        // Waveform trace (green, 3-pixel wide)
        else if (pixel_y >= ((dds_y > 2) ? dds_y - 2 : 0) &&
                 pixel_y <= ((dds_y < 477) ? dds_y + 2 : 479)) begin
            sggen_r = 4'h0; sggen_g = 4'hF; sggen_b = 4'h0;
        end
        // Modulation envelope indicator (dimmer)
        else if (mod_enable && pixel_y >= ((dds_y > 3) ? dds_y - 3 : 0) &&
                 pixel_y <= ((dds_y < 476) ? dds_y + 3 : 479) &&
                 pixel_x[0]) begin
            sggen_r = 4'h0; sggen_g = 4'h6; sggen_b = 4'h0;
        end
        else begin
            sggen_r = 4'h0; sggen_g = 4'h0; sggen_b = 4'h0;
        end
    end else begin
        sggen_r = 4'h0; sggen_g = 4'h0; sggen_b = 4'h0;
    end
end

//=============================================================================
// Mode MUX — select which display drives VGA
//=============================================================================
assign vga_r = (device_mode == 2'b00) ? sggen_r :
               (device_mode == 2'b10) ? liss_r   :
               (device_mode == 2'b11) ? kalei_r  : scope_r;

assign vga_g = (device_mode == 2'b00) ? sggen_g :
               (device_mode == 2'b10) ? liss_g   :
               (device_mode == 2'b11) ? kalei_g  : scope_g;

assign vga_b = (device_mode == 2'b00) ? sggen_b :
               (device_mode == 2'b10) ? liss_b   :
               (device_mode == 2'b11) ? kalei_b  : scope_b;

//=============================================================================
// Status LEDs & Loopback
//=============================================================================
assign led_speed[0] = (device_mode == 2'b00);   // Sig Gen
assign led_speed[1] = (device_mode == 2'b01);   // Scope
assign led_speed[2] = (device_mode == 2'b10 || device_mode == 2'b11);  // XY modes

// Loopback: echo rx to tx for self-test
assign loop_tx = loop_rx;

endmodule
