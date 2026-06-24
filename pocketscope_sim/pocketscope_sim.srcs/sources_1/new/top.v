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
    input  wire          adc_vauxp2, adc_vauxn2,
    input  wire          adc_vauxp3, adc_vauxn3,
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

// DAC output: modulated signal or amplitude-scaled DDS output
wire [7:0] dac_data_in;
wire       dac_update;

// Bipolar amplitude scaling: preserve 0x80 (zero) center
// Scale only the deviation from center, keep DC at 0x80
wire signed [8:0]  dds_dev  = $signed({1'b0, dds_wave_out}) - 9'sd128;
wire signed [8:0]  amp_s    = $signed({1'b0, amplitude});
wire signed [17:0] dds_prod = dds_dev * amp_s;
wire [7:0]         dds_amp  = 8'd128 + dds_prod[15:8];

assign dac_data_in = mod_enable ? mod_signal_out : dds_amp;

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
// Map physical ADC inputs to XADC VAUXP/VAUXN buses
wire [15:0] xadc_vauxp, xadc_vauxn;
// VAUXP/VAUXN bus mapping to XADC auxiliary channels:
//   [15:4] = unused
//   [3]    = adc_vauxp3/vauxn3  (AD3, auxiliary channel 3, DRP addr 0x13)
//   [2]    = adc_vauxp2/vauxn2  (AD2, auxiliary channel 2, DRP addr 0x12)
//   [1:0]  = unused
assign xadc_vauxp = {12'd0, adc_vauxp3, adc_vauxp2, 2'b00};
assign xadc_vauxn = {12'd0, adc_vauxn3, adc_vauxn2, 2'b00};

wire [11:0] adc_ch1_raw, adc_ch2_raw;
wire        adc_ch1_vld, adc_ch2_vld;

xadc_reader #(
    .SIM_MODE(0),
    .USE_4053(1),           // 1 = single XADC channel + 4053 mux
    .SINGLE_CH_ADDR(7'h12), // VAUXP[2]/VAUXN[2] carries the muxed signal
    .SETTLE_CYCLES(10)      // 100ns settle time at 100MHz (> 74HC4053 t_on=60ns)
) u_xadc (
    .clk(sys_clk), .rst_n(rst_n),
    .vp_in(adc_p_in), .vn_in(adc_n_in),
    .vauxp(xadc_vauxp), .vauxn(xadc_vauxn),
    .ch1_data(adc_ch1_raw), .ch1_valid(adc_ch1_vld),
    .ch2_data(adc_ch2_raw), .ch2_valid(adc_ch2_vld),
    .mux_sel(mux_sel)
);

// 12-bit to 8-bit conversion
wire [7:0] adc_ch1_8b, adc_ch2_8b;
assign adc_ch1_8b = adc_ch1_raw[11:4];
assign adc_ch2_8b = adc_ch2_raw[11:4];

//=============================================================================
// Waveform Storage (Dual Channel RAM)
//=============================================================================
wire [9:0] wr_addr;
wire [9:0] scroll_shift;
wire       de;
wire [9:0] pixel_x, pixel_y;

scroll_addr_gen u_scroll (
    .clk(clk_25m), .rst_n(rst_n),
    .pixel_x(pixel_x),
    .display_addr(wr_addr),
    .shift(scroll_shift)
);

wire [7:0] wave_ch1, wave_ch2;
wire [9:0] display_addr = wr_addr;

wave_ram_ch1 u_ram_ch1 (
    .clk(clk_25m),
    .we(adc_ch1_vld), .wr_addr(wr_addr), .din(adc_ch1_8b),
    .rd_addr(display_addr), .dout(wave_ch1)
);

wave_ram_ch2 u_ram_ch2 (
    .clk(clk_25m),
    .we(adc_ch2_vld), .wr_addr(wr_addr), .din(adc_ch2_8b),
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
// Waveform Analyzers (Frequency, Vpp, Type)
//=============================================================================
wire [15:0] freq_ch1, freq_ch2;
wire [7:0]  vpp_ch1, vpp_ch2;
wire [1:0]  type_ch1, type_ch2;
wire        meas_valid_ch1, meas_valid_ch2;

wave_analyzer u_analyzer_ch1 (
    .clk(clk_25m), .rst_n(rst_n),
    .wave_data(adc_ch1_8b), .wave_valid(adc_ch1_vld),
    .frequency_hz(freq_ch1), .vpp(vpp_ch1),
    .wave_type_det(type_ch1), .meas_valid(meas_valid_ch1)
);

wave_analyzer u_analyzer_ch2 (
    .clk(clk_25m), .rst_n(rst_n),
    .wave_data(adc_ch2_8b), .wave_valid(adc_ch2_vld),
    .frequency_hz(freq_ch2), .vpp(vpp_ch2),
    .wave_type_det(type_ch2), .meas_valid(meas_valid_ch2)
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
    .vga_r(scope_r), .vga_g(scope_g), .vga_b(scope_b)
);

// 2) Lissajous X-Y mode
wire [3:0] liss_r, liss_g, liss_b;

lissajous_display u_liss (
    .clk(clk_25m), .rst_n(rst_n), .de(de),
    .pixel_x(pixel_x), .pixel_y(pixel_y),
    .ch1_data(adc_ch1_8b), .ch2_data(adc_ch2_8b),
    .ch1_valid(adc_ch1_vld), .ch2_valid(adc_ch2_vld),
    .vga_r(liss_r), .vga_g(liss_g), .vga_b(liss_b)
);

// 3) Kaleidoscope mode
wire [3:0] kalei_r, kalei_g, kalei_b;

kaleidoscope u_kalei (
    .clk(clk_25m), .rst_n(rst_n), .de(de),
    .pixel_x(pixel_x), .pixel_y(pixel_y),
    .ch1_data(adc_ch1_8b), .ch2_data(adc_ch2_8b),
    .ch1_valid(adc_ch1_vld), .ch2_valid(adc_ch2_vld),
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
