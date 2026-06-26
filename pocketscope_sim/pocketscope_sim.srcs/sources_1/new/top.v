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
    input  wire          adc_vauxp2, adc_vauxn2, // ADC_MUX_OUT J5 pins 9-10 (VAUXP[2]/N[2])
    // UI
    input  wire [4:0]    btn,
    input  wire [7:0]    sw_in,
    input  wire [7:0]    sw_dip,
    // Status / loopback
    output wire [2:0]    led_speed,
    output wire [3:0]    loop_tx,       // loop_tx[0] repurposed as mux_sel
    input  wire [3:0]    loop_rx,
    // 4053 analog switch control (expansion board)
    output wire          mux_sel        // 0=CH1, 1=CH2 (toggled each sample)
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

// Recalculate frequency in Hz from switches (for signal gen display overlay)
// Same formula as ui_ctrl — avoids adding output port to ui_ctrl interface
wire [2:0]  sg_coarse = sw_in[7:5];
wire [15:0] sg_freq_unclamped =
    (sg_coarse == 3'd0) ? (16'd100  + {8'b0, sw_dip} * 16'd20) :
    (sg_coarse == 3'd1) ? (16'd2000 + {8'b0, sw_dip} * 16'd20) :
    (sg_coarse == 3'd2) ? (16'd4000 + {8'b0, sw_dip} * 16'd20) :
    (sg_coarse == 3'd3) ? (16'd6000 + {8'b0, sw_dip} * 16'd20) :
    (sg_coarse == 3'd4) ? (16'd8000 + {8'b0, sw_dip} * 16'd20) :
    16'd1000;
wire [15:0] freq_hz =
    (sg_freq_unclamped < 16'd100)   ? 16'd100   :
    (sg_freq_unclamped > 16'd10000) ? 16'd10000 :
    sg_freq_unclamped;

//=============================================================================
// DDS Signal Generator
//=============================================================================
wire [1:0] dds_wave_type;
assign dds_wave_type = sig_gen_submode[2] ? 2'b00 : sig_gen_submode[1:0];

wire [7:0]  dds_wave_out;
wire [23:0] dds_ftw_in;

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
// Use dac_prod[17:8] — bit 17 is the true sign bit, avoids fragile
// sign-extension that relied on bit[16]==bit[17] for limited amplitude range
wire signed [9:0]  dac_sum   = $signed(dac_prod[17:8]) + 10'sd128;
wire [7:0]         dac_data_in = dac_sum[9] ? 8'd0 :        // negative → clamp to 0
                                  dac_sum[8] ? 8'd255 :       // >255 → clamp to 255
                                               dac_sum[7:0]; // 0–255 pass through

wire dac_update;

// DAC update rate divider (25MHz / 24 ≈ 1.04MHz)
// 24-cycle period = 960ns, WR# pulse = 16 cycles (640ns), gives 320ns idle gap.
// Increased from 64 (390kHz) to reduce square-wave edge jitter and improve
// waveform fidelity. DAC0832 settling time ~1µs limits useful update rate.
reg [4:0]  dac_rate_cnt;
reg        dac_update_trig;

always @(posedge clk_25m or negedge rst_n) begin
    if (!rst_n) begin
        dac_rate_cnt <= 0;
        dac_update_trig <= 0;
    end else begin
        dac_update_trig <= 0;
        if (dac_rate_cnt == 23) begin
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
// Signal Generator Waveform Buffer (1024-sample ring buffer)
// Captures DDS output at ~1.56MHz for stable, non-jumping VGA preview.
// Same architecture as oscilloscope wave_ram — write pointer advances,
// VGA reads from (wr_ptr - 640 + pixel_x) for a scrolling trace.
//=============================================================================
reg [7:0] sg_ram [0:1023];
reg [9:0] sg_wr_ptr;
reg [4:0] sg_sample_div;

always @(posedge clk_25m or negedge rst_n) begin
    if (!rst_n) begin
        sg_wr_ptr     <= 10'd0;
        sg_sample_div <= 5'd0;
    end else if (device_mode == 2'b00) begin
        if (sg_sample_div == 5'd15) begin
            sg_sample_div <= 5'd0;
            sg_ram[sg_wr_ptr] <= dds_wave_out;
            sg_wr_ptr <= sg_wr_ptr + 1'b1;
        end else begin
            sg_sample_div <= sg_sample_div + 1'b1;
        end
    end else begin
        sg_sample_div <= 5'd0;
    end
end

// Ring-buffer read address: 640-sample window ending at current write position
wire [9:0] sg_rd_addr = (sg_wr_ptr - 10'd640 + pixel_x);

reg [7:0] sg_rd_data;
always @(posedge clk_25m)
    sg_rd_data <= sg_ram[sg_rd_addr];

// Map 8-bit sample to Y coordinate (waveform area y=0..431)
wire [9:0] sg_y = 10'd431 - ((sg_rd_data * 10'd431) >> 8);

//=============================================================================
// Signal Generator Parameter Text Overlay
//=============================================================================
// Simple 3-row text bar at y=456-479 (24 rows, 3 char-rows of 8px each)
//   Row 0: "SG F:#####Hz A:### W:XXXX"
//   Row 1: "   MOD:XX DEP:###"
//   Row 2: "   PB0/1:Amp PB2/3:Dep"
//=============================================================================
wire sg_in_bar = (pixel_y >= 10'd456);

// Character generator addressing (same scheme as waveform_display)
wire [2:0] sg_char_row  = pixel_y[2:0];
wire [2:0] sg_char_col  = pixel_x[2:0];
wire [6:0] sg_char_cx   = pixel_x[9:3];
wire [1:0] sg_char_cy   = (pixel_y - 10'd456) >> 3;  // char row 0..2

// Frequency digits
wire [3:0] sg_f_d5 = (freq_hz / 16'd10000) % 4'd10;
wire [3:0] sg_f_d4 = (freq_hz / 16'd1000)  % 4'd10;
wire [3:0] sg_f_d3 = (freq_hz / 16'd100)   % 4'd10;
wire [3:0] sg_f_d2 = (freq_hz / 16'd10)    % 4'd10;
wire [3:0] sg_f_d1 = (freq_hz)             % 4'd10;

// Amplitude digits (0-255 range, display as raw for now)
wire [3:0] sg_a_d3 = (amplitude / 8'd100) % 4'd10;
wire [3:0] sg_a_d2 = (amplitude / 8'd10)  % 4'd10;
wire [3:0] sg_a_d1 = (amplitude)          % 4'd10;

// Mod depth digits
wire [3:0] sg_md_d3 = (mod_depth / 8'd100) % 4'd10;
wire [3:0] sg_md_d2 = (mod_depth / 8'd10)  % 4'd10;
wire [3:0] sg_md_d1 = (mod_depth)          % 4'd10;

function [7:0] sg_d2a;
    input [3:0] d;
    begin
        sg_d2a = {4'h3, d};
    end
endfunction

// Waveform type string
function [7:0] sg_wave_char;
    input [2:0] submode;
    begin
        case (submode[1:0])
            2'b01:   sg_wave_char = 8'h53;  // 'S' = Square
            2'b10:   sg_wave_char = 8'h54;  // 'T' = Triangle
            default: sg_wave_char = 8'h4E;  // 'N' = siNe
        endcase
    end
endfunction

// Modulation type string
function [7:0] sg_mod_char;
    input [1:0] mt;
    begin
        case (mt)
            2'b00: sg_mod_char = 8'h41;  // 'A' = AM
            2'b01: sg_mod_char = 8'h46;  // 'F' = FM
            2'b10: sg_mod_char = 8'h50;  // 'P' = SPWM
            default: sg_mod_char = 8'h20; // space
        endcase
    end
endfunction

reg [7:0] sg_char;
always @(*) begin
    sg_char = 8'h20;  // default: space
    case (sg_char_cy)
        // Row 0: "SG F:#####Hz A:### W:X"
        2'd0: begin
            case (sg_char_cx)
                7'd0:  sg_char = 8'h53;  // 'S'
                7'd1:  sg_char = 8'h47;  // 'G'
                7'd2:  sg_char = 8'h20;  // ' '
                7'd3:  sg_char = 8'h46;  // 'F'
                7'd4:  sg_char = 8'h3A;  // ':'
                7'd5:  sg_char = sg_d2a(sg_f_d5);
                7'd6:  sg_char = sg_d2a(sg_f_d4);
                7'd7:  sg_char = sg_d2a(sg_f_d3);
                7'd8:  sg_char = sg_d2a(sg_f_d2);
                7'd9:  sg_char = sg_d2a(sg_f_d1);
                7'd10: sg_char = 8'h48;  // 'H'
                7'd11: sg_char = 8'h7A;  // 'z'
                7'd12: sg_char = 8'h20;  // ' '
                7'd13: sg_char = 8'h41;  // 'A'
                7'd14: sg_char = 8'h3A;  // ':'
                7'd15: sg_char = sg_d2a(sg_a_d3);
                7'd16: sg_char = sg_d2a(sg_a_d2);
                7'd17: sg_char = sg_d2a(sg_a_d1);
                7'd18: sg_char = 8'h20;  // ' '
                7'd19: sg_char = 8'h57;  // 'W'
                7'd20: sg_char = 8'h3A;  // ':'
                7'd21: sg_char = sg_wave_char(sig_gen_submode);
                default: sg_char = 8'h20;
            endcase
        end
        // Row 1: "   MOD:X DEP:###"
        2'd1: begin
            case (sg_char_cx)
                7'd0:  sg_char = 8'h20;  // ' '
                7'd1:  sg_char = 8'h20;  // ' '
                7'd2:  sg_char = 8'h20;  // ' '
                7'd3:  sg_char = 8'h4D;  // 'M'
                7'd4:  sg_char = 8'h4F;  // 'O'
                7'd5:  sg_char = 8'h44;  // 'D'
                7'd6:  sg_char = 8'h3A;  // ':'
                7'd7:  sg_char = mod_enable ? sg_mod_char(mod_type) : 8'h4F;  // 'O'=Off or A/F/P
                7'd8:  sg_char = mod_enable ? 8'h20 : 8'h46;  // 'F'=ofF
                7'd9:  sg_char = mod_enable ? 8'h20 : 8'h46;  // 'F'
                7'd10: sg_char = 8'h20;  // ' '
                7'd11: sg_char = 8'h44;  // 'D'
                7'd12: sg_char = 8'h45;  // 'E'
                7'd13: sg_char = 8'h50;  // 'P'
                7'd14: sg_char = 8'h3A;  // ':'
                7'd15: sg_char = sg_d2a(sg_md_d3);
                7'd16: sg_char = sg_d2a(sg_md_d2);
                7'd17: sg_char = sg_d2a(sg_md_d1);
                default: sg_char = 8'h20;
            endcase
        end
        // Row 2: "   PB0/1:+/-A PB2/3:+/-D"
        2'd2: begin
            case (sg_char_cx)
                7'd0:  sg_char = 8'h20;  // ' '
                7'd1:  sg_char = 8'h20;  // ' '
                7'd2:  sg_char = 8'h20;  // ' '
                7'd3:  sg_char = 8'h50;  // 'P'
                7'd4:  sg_char = 8'h42;  // 'B'
                7'd5:  sg_char = 8'h30;  // '0'
                7'd6:  sg_char = 8'h2F;  // '/'
                7'd7:  sg_char = 8'h31;  // '1'
                7'd8:  sg_char = 8'h3A;  // ':'
                7'd9:  sg_char = 8'h41;  // 'A'
                7'd10: sg_char = 8'h6D;  // 'm'
                7'd11: sg_char = 8'h70;  // 'p'
                7'd12: sg_char = 8'h20;  // ' '
                7'd13: sg_char = 8'h50;  // 'P'
                7'd14: sg_char = 8'h42;  // 'B'
                7'd15: sg_char = 8'h32;  // '2'
                7'd16: sg_char = 8'h2F;  // '/'
                7'd17: sg_char = 8'h33;  // '3'
                7'd18: sg_char = 8'h3A;  // ':'
                7'd19: sg_char = 8'h44;  // 'D'
                7'd20: sg_char = 8'h65;  // 'e'
                7'd21: sg_char = 8'h70;  // 'p'
                default: sg_char = 8'h20;
            endcase
        end
        default: sg_char = 8'h20;
    endcase
end

// Char gen for signal generator overlay text
wire sg_char_on;
char_gen u_sg_char (
    .clk(clk_25m),
    .char_code(sg_char),
    .char_row(sg_char_row),
    .char_col(sg_char_col),
    .pixel_on(sg_char_on)
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
//   [3]    = 0 (VAUXP[3]/VAUXN[3] unused — USE_4053=1, only VAUXP[2] needed)
//   [2]    = adc_vauxp2/vauxn2  (AD2, auxiliary channel 2, DRP addr 0x12 — ADC_MUX_OUT)
//   [1]    = unused
//   [0]    = unused
assign xadc_vauxp = {12'd0, 1'b0, adc_vauxp2, 2'b0};
assign xadc_vauxn = {12'd0, 1'b0, adc_vauxn2, 2'b0};

wire [11:0] adc_ch1_raw, adc_ch2_raw;
wire        adc_ch1_vld, adc_ch2_vld;

// XADC DRP handshake debug signals (for ILA monitoring)
wire        dbg_drp_drdy, dbg_drp_den, dbg_settling, dbg_den_pending, dbg_startup_done;

xadc_reader #(
    .SIM_MODE(0),
    .USE_4053(1),           // 1 = single XADC channel + 4053 mux
    .SINGLE_CH_ADDR(7'h12), // VAUXP[2]/VAUXN[2] (AD2, J5 pins 9-10) carries the muxed signal
    .SETTLE_CYCLES(10)      // 100ns settle time at 100MHz (> 74HC4053 t_on=60ns)
) u_xadc (
    .clk(sys_clk), .rst_n(rst_n),
    .vp_in(adc_p_in), .vn_in(adc_n_in),
    .vauxp(xadc_vauxp), .vauxn(xadc_vauxn),
    .ch1_data(adc_ch1_raw), .ch1_valid(adc_ch1_vld),
    .ch2_data(adc_ch2_raw), .ch2_valid(adc_ch2_vld),
    .mux_sel(mux_sel),
    .sample_rate_hz(sample_rate_hz_sys),
    .sample_rate_update(sample_rate_update_sys),
    .dbg_drp_drdy(dbg_drp_drdy),
    .dbg_drp_den(dbg_drp_den),
    .dbg_settling(dbg_settling),
    .dbg_den_pending(dbg_den_pending),
    .dbg_startup_done(dbg_startup_done)
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
wire       de;
wire [9:0] pixel_x, pixel_y;

// Trigger resets the write address to align trigger point with screen center
// (center = 512 pixels into the 1024-sample buffer)
wire trigger_reset;
assign trigger_reset = trigger_event && (device_mode == 2'b01);

// Sequential write address: increments on each CH2 valid (CH1+CH2 pair
// complete in 4053 mux mode). CH1 and CH2 write to the SAME address so
// they share the same horizontal position on screen.
reg [9:0] sample_wr_addr;

always @(posedge clk_25m or negedge rst_n) begin
    if (!rst_n)
        sample_wr_addr <= 10'd0;
    else if (trigger_reset)
        sample_wr_addr <= 10'd512;  // align trigger point to buffer center
    else if (adc_ch2_vld_25m)
        sample_wr_addr <= sample_wr_addr + 1'b1;
end

// Display read address: show the last 640 samples before current write pos.
// pixel_x=0 → oldest visible sample; pixel_x=639 → newest visible sample.
// 10-bit unsigned underflow naturally implements modulo-1024 wrap.
wire [9:0] display_addr = (sample_wr_addr - 10'd640 + pixel_x);

wire [7:0] wave_ch1, wave_ch2;

wave_ram_ch1 u_ram_ch1 (
    .clk(clk_25m),
    .we(adc_ch1_vld_25m), .wr_addr(sample_wr_addr), .din(adc_ch1_8b),
    .rd_addr(display_addr), .dout(wave_ch1)
);

wave_ram_ch2 u_ram_ch2 (
    .clk(clk_25m),
    .we(adc_ch2_vld_25m), .wr_addr(sample_wr_addr), .din(adc_ch2_8b),
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

// 4) Signal Generator preview — stable waveform from ring buffer + parameter overlay
reg [3:0] sggen_r, sggen_g, sggen_b;

always @(*) begin
    sggen_r = 4'h0;
    sggen_g = 4'h0;
    sggen_b = 4'h0;

    if (de) begin
        //---- Text overlay bar (y=456..479) ----
        if (sg_in_bar) begin
            // Dark background
            sggen_r = 4'h1; sggen_g = 4'h1; sggen_b = 4'h1;

            // Separator line at top of text bar
            if (pixel_y == 456) begin
                sggen_r = 4'h8; sggen_g = 4'h8; sggen_b = 4'h8;
            end

            // Row 0 background: warm tint
            if (sg_char_cy == 2'd0) begin
                sggen_r = 4'h2; sggen_g = 4'h1; sggen_b = 4'h0;
            end
            // Row 1 background: cool tint
            if (sg_char_cy == 2'd1) begin
                sggen_r = 4'h0; sggen_g = 4'h1; sggen_b = 4'h2;
            end
            // Row 2 background: dim
            if (sg_char_cy == 2'd2) begin
                sggen_r = 4'h1; sggen_g = 4'h1; sggen_b = 4'h1;
            end

            // Character pixels — bright green for rows 0-1, dim for row 2
            if (sg_char_on) begin
                if (sg_char_cy == 2'd0) begin
                    sggen_r = 4'hF; sggen_g = 4'hF; sggen_b = 4'h0;  // yellow
                end else if (sg_char_cy == 2'd1) begin
                    sggen_r = 4'h0; sggen_g = 4'hF; sggen_b = 4'hF;  // cyan
                end else begin
                    sggen_r = 4'h8; sggen_g = 4'h8; sggen_b = 4'h8;  // gray
                end
            end
        end
        //---- Waveform Area (y=0..455) ----
        else begin
            // Grid
            if ((pixel_x % 80) == 0 || (pixel_y % 60) == 0) begin
                sggen_r = 4'h2; sggen_g = 4'h2; sggen_b = 4'h2;
            end
            // Center cross
            if (pixel_x == 320 || pixel_y == 228) begin
                sggen_r = 4'h4; sggen_g = 4'h4; sggen_b = 4'h4;
            end
            // Waveform trace from RAM buffer — 3-pixel wide green line
            // sg_rd_data has 1-cycle read latency, so trace lags 1 pixel
            // behind sg_rd_addr — imperceptible on a 640-pixel scanline
            if (pixel_y >= ((sg_y > 1) ? sg_y - 1 : 0) &&
                pixel_y <= ((sg_y < 454) ? sg_y + 1 : 455)) begin
                sggen_r = 4'h0; sggen_g = 4'hF; sggen_b = 4'h0;
            end
        end
    end
end

//=============================================================================
// Mode MUX — select which display drives VGA
//=============================================================================
// Signal generator mode: DAC outputs the waveform directly — VGA stays blank.
// Other modes drive VGA as before.
assign vga_r = (device_mode == 2'b00) ? 4'h0 :
               (device_mode == 2'b10) ? liss_r   :
               (device_mode == 2'b11) ? kalei_r  : scope_r;

assign vga_g = (device_mode == 2'b00) ? 4'h0 :
               (device_mode == 2'b10) ? liss_g   :
               (device_mode == 2'b11) ? kalei_g  : scope_g;

assign vga_b = (device_mode == 2'b00) ? 4'h0 :
               (device_mode == 2'b10) ? liss_b   :
               (device_mode == 2'b11) ? kalei_b  : scope_b;

//=============================================================================
// Status LEDs & Loopback
//=============================================================================
assign led_speed[0] = (device_mode == 2'b00);   // Sig Gen
assign led_speed[1] = (device_mode == 2'b01);   // Scope
assign led_speed[2] = (device_mode == 2'b10 || device_mode == 2'b11);  // XY modes

// Loopback: echo rx to tx for self-test
// loop_tx[0] carries mux_sel for 74HC4053 analog switch control
assign loop_tx = {loop_rx[3:1], mux_sel};

//=============================================================================
// ILA Debug Probe — ADC signal chain monitoring
//=============================================================================
// Resynchronize 25MHz-domain signals into sys_clk (100MHz) domain for ILA.
// 2-stage synchronizers prevent metastability in the debug capture path.
// These are DEBUG-ONLY; they do not affect functional data paths.

// --- 2-stage synchronizers for 25MHz → 100MHz signals ---
reg        ila_ch1_vld_25m_s1, ila_ch1_vld_25m_s2;
reg        ila_ch2_vld_25m_s1, ila_ch2_vld_25m_s2;
reg [7:0]  ila_ch1_8b_s1,     ila_ch1_8b_s2;
reg [7:0]  ila_ch2_8b_s1,     ila_ch2_8b_s2;
reg        ila_trig_fired_s1,  ila_trig_fired_s2;
reg        ila_trig_armed_s1,  ila_trig_armed_s2;
reg [9:0]  ila_wr_addr_s1,    ila_wr_addr_s2;
reg [1:0]  ila_mode_s1,       ila_mode_s2;
reg        ila_clk25m_s1,      ila_clk25m_s2;

always @(posedge sys_clk) begin
    // CH1 valid
    ila_ch1_vld_25m_s1 <= adc_ch1_vld_25m;
    ila_ch1_vld_25m_s2 <= ila_ch1_vld_25m_s1;
    // CH2 valid
    ila_ch2_vld_25m_s1 <= adc_ch2_vld_25m;
    ila_ch2_vld_25m_s2 <= ila_ch2_vld_25m_s1;
    // CH1 8-bit data
    ila_ch1_8b_s1 <= adc_ch1_8b;
    ila_ch1_8b_s2 <= ila_ch1_8b_s1;
    // CH2 8-bit data
    ila_ch2_8b_s1 <= adc_ch2_8b;
    ila_ch2_8b_s2 <= ila_ch2_8b_s1;
    // Trigger fired
    ila_trig_fired_s1 <= trigger_fired;
    ila_trig_fired_s2 <= ila_trig_fired_s1;
    // Trigger armed
    ila_trig_armed_s1 <= trigger_armed;
    ila_trig_armed_s2 <= ila_trig_armed_s1;
    // Write address
    ila_wr_addr_s1 <= sample_wr_addr;
    ila_wr_addr_s2 <= ila_wr_addr_s1;
    // Device mode
    ila_mode_s1 <= device_mode;
    ila_mode_s2 <= ila_mode_s1;
    // 25MHz clock sampled as reference
    ila_clk25m_s1 <= clk_25m;
    ila_clk25m_s2 <= ila_clk25m_s1;
end

// --- Probe bus assembly ---
// See ila_adc_debug.v for complete bit-mapping documentation
wire [63:0] ila_probe;
assign ila_probe = {
    ila_mode_s2,          // [63:62] device_mode
    mux_sel,              // [61]    4053 channel select
    adc_ch1_vld,          // [60]    CH1 valid raw (XADC)
    adc_ch2_vld,          // [59]    CH2 valid raw (XADC)
    dbg_drp_drdy,         // [58]    DRP data-ready from XADC
    dbg_drp_den,          // [57]    DRP enable to XADC
    dbg_settling,         // [56]    4053 settle wait state
    dbg_den_pending,      // [55]    DEN pending flag
    dbg_startup_done,     // [54]    XADC startup calibration done
    ila_trig_fired_s2,    // [53]    scope trigger fired
    ila_wr_addr_s2,       // [52:43] sample write address
    adc_ch1_raw,          // [42:31] CH1 raw 12-bit XADC
    adc_ch2_raw,          // [30:19] CH2 raw 12-bit XADC
    ila_ch1_8b_s2,        // [18:11] CH1 8-bit scope data
    ila_ch2_8b_s2,        // [10:3]  CH2 8-bit scope data
    ila_clk25m_s2,        // [2]     25MHz clock reference
    2'b00                 // [1:0]   reserved
};

// --- ILA Core instantiation ---
ila_adc_debug u_ila_adc (
    .clk   (sys_clk),
    .probe (ila_probe)
);

endmodule
