`timescale 1ns / 1ps
//=============================================================================
// Waveform Display Module — Laboratory Oscilloscope Style
// Dual-channel display with professional graticule, traces, and metrics.
//
// Screen layout: 640×480
//   Waveform area: y=0..431 (432 rows — 8 vertical divisions × 54 pixels each)
//   Metrics bar:   y=432..479 (48 rows — 6 character rows of 8px each)
//
// Grid: 8×10 divisions (80×54 pixel cells) with center crosshair
//
// Metrics bar (6 rows × 80 chars, y=432..479):
//   Row 0: "CH1 F:##### T:####us Vpp:####mV D:##% W:XXXXX"
//   Row 1: "    Vrms:### Vavg:### Vmax:### Vmin:###mV     "
//   Row 2: "CH2 F:##### T:####us Vpp:####mV D:##% W:XXXXX"
//   Row 3: "    Vrms:### Vavg:### Vmax:### Vmin:###mV     "
//   Row 4: "CF1:#### CF2:#### RT1:## RT2:##us  (CF×100)  "
//   Row 5: "ADC:#####k TRG:###mV STA:XXXXX                "
//=============================================================================

module waveform_display
(
    input  wire          clk,
    input  wire          de,
    input  wire [9:0]    pixel_x,
    input  wire [9:0]    pixel_y,

    // Waveform RAM data
    input  wire [7:0]    wave_ch1,
    input  wire [7:0]    wave_ch2,

    // ---- Metrics from wave_analyzer ----
    // CH1
    input  wire [15:0]   freq_ch1,
    input  wire [15:0]   period_ch1_x100us,
    input  wire [7:0]    vpp_ch1,
    input  wire [7:0]    vmin_ch1,
    input  wire [2:0]    type_ch1,
    input  wire [6:0]    duty_ch1,
    input  wire [7:0]    rise_time_ch1,
    input  wire [10:0]   crest_ch1_x100,
    input  wire [7:0]    rms_ch1,
    input  wire [7:0]    avg_ch1,
    input  wire [7:0]    max_ch1,
    input  wire [15:0]   vpp_mv_ch1,
    input  wire [15:0]   vmin_mv_ch1,
    input  wire [15:0]   rms_mv_ch1,
    input  wire [15:0]   avg_mv_ch1,
    input  wire [15:0]   max_mv_ch1,

    // CH2
    input  wire [15:0]   freq_ch2,
    input  wire [15:0]   period_ch2_x100us,
    input  wire [7:0]    vpp_ch2,
    input  wire [7:0]    vmin_ch2,
    input  wire [2:0]    type_ch2,
    input  wire [6:0]    duty_ch2,
    input  wire [7:0]    rise_time_ch2,
    input  wire [10:0]   crest_ch2_x100,
    input  wire [7:0]    rms_ch2,
    input  wire [7:0]    avg_ch2,
    input  wire [7:0]    max_ch2,
    input  wire [15:0]   vpp_mv_ch2,
    input  wire [15:0]   vmin_mv_ch2,
    input  wire [15:0]   rms_mv_ch2,
    input  wire [15:0]   avg_mv_ch2,
    input  wire [15:0]   max_mv_ch2,

    input  wire          meas_valid,

    // Sample rate + trigger
    input  wire [15:0]   sample_rate_hz,
    input  wire          trigger_armed,
    input  wire [7:0]    trigger_level,

    // VGA output
    output reg  [3:0]    vga_r,
    output reg  [3:0]    vga_g,
    output reg  [3:0]    vga_b
);

    //=========================================================================
    // Grid parameters — 8×10 divisions
    // Waveform area: 640×432 (y=0..431). V_div=54px, H_div=80px.
    // Center: (320, 216)
    //=========================================================================
    localparam WAVEFORM_TOP    = 10'd0;
    localparam WAVEFORM_BOTTOM = 10'd431;
    localparam WAVEFORM_HEIGHT = 10'd432;  // 0..431 inclusive
    localparam CENTER_X = 10'd320;
    localparam CENTER_Y = 10'd216;

    localparam H_DIV = 10'd80;   // pixels per horizontal division
    localparam V_DIV = 10'd54;   // pixels per vertical division (432/8=54)

    //=========================================================================
    // ADC value -> Y coordinate (mapped to waveform area: 0->431)
    // 8-bit value 0-255 maps linearly to 431 down to 0
    //=========================================================================
    wire [9:0] wave_y_ch1 = WAVEFORM_BOTTOM - ((wave_ch1 * WAVEFORM_HEIGHT) >> 8);
    wire [9:0] wave_y_ch2 = WAVEFORM_BOTTOM - ((wave_ch2 * WAVEFORM_HEIGHT) >> 8);

    //=========================================================================
    // Grid & Graticule — Professional oscilloscope style
    //=========================================================================
    // Major grid lines at each division boundary
    wire major_grid_x = ((pixel_x % H_DIV) == 0);
    wire major_grid_y = ((pixel_y % V_DIV) == 0) && (pixel_y < WAVEFORM_HEIGHT);

    // Minor grid dots every 20px horizontal, every 13-14px vertical (quarter divs)
    wire minor_grid_x = ((pixel_x % 20) == 0);
    wire minor_grid_y = ((pixel_y % 13) == 0) && (pixel_y < WAVEFORM_HEIGHT);

    // Center crosshair (full width/height)
    wire center_line_x = (pixel_y == CENTER_Y) && (pixel_y < WAVEFORM_HEIGHT);
    wire center_line_y = (pixel_x == CENTER_X);

    //=========================================================================
    // Waveform hit detection (3-pixel wide traces, clamped to waveform area)
    //=========================================================================
    wire hit_ch1 = (pixel_y >= ((wave_y_ch1 > 1) ? wave_y_ch1 - 1 : 0)) &&
                   (pixel_y <= ((wave_y_ch1 < (WAVEFORM_BOTTOM - 1)) ? wave_y_ch1 + 1 : WAVEFORM_BOTTOM));
    wire hit_ch2 = (pixel_y >= ((wave_y_ch2 > 1) ? wave_y_ch2 - 1 : 0)) &&
                   (pixel_y <= ((wave_y_ch2 < (WAVEFORM_BOTTOM - 1)) ? wave_y_ch2 + 1 : WAVEFORM_BOTTOM));

    // Clipping indicators: signal out of range
    wire clip_ch1_high = (wave_ch1 >= 8'd252) && hit_ch1;
    wire clip_ch1_low  = (wave_ch1 <= 8'd3)   && hit_ch1;
    wire clip_ch2_high = (wave_ch2 >= 8'd252) && hit_ch2;
    wire clip_ch2_low  = (wave_ch2 <= 8'd3)   && hit_ch2;

    //=========================================================================
    // Metrics Bar Area (y=432..479, 48 rows = 6 char rows)
    //=========================================================================
    wire in_metrics_bar = (pixel_y >= 432);

    //=========================================================================
    // Character Generator addressing
    //=========================================================================
    wire [2:0] char_col = pixel_x[2:0];
    wire [2:0] char_row = pixel_y[2:0];
    wire [6:0] char_cell_x = pixel_x[9:3];
    wire [2:0] char_cell_y = (pixel_y - 10'd432) >> 3;  // char row 0-5

    //=========================================================================
    // Helper: BCD digit to ASCII
    //=========================================================================
    function [7:0] digit_to_ascii;
        input [3:0] digit;
        begin
            digit_to_ascii = {4'h3, digit};
        end
    endfunction

    //=========================================================================
    // Waveform type display string — 5 characters
    //=========================================================================
    function [39:0] type_string;  // 5 chars × 8 bits
        input [2:0] t;
        begin
            case (t)
                3'b001:  type_string = {8'h53, 8'h51, 8'h55, 8'h41, 8'h52}; // "SQUAR"
                3'b010:  type_string = {8'h54, 8'h52, 8'h49, 8'h20, 8'h20}; // "TRI  "
                3'b011:  type_string = {8'h53, 8'h41, 8'h57, 8'h20, 8'h20}; // "SAW  "
                3'b100:  type_string = {8'h44, 8'h43, 8'h20, 8'h20, 8'h20}; // "DC   "
                3'b101:  type_string = {8'h4E, 8'h4F, 8'h49, 8'h53, 8'h45}; // "NOISE"
                default: type_string = {8'h53, 8'h49, 8'h4E, 8'h45, 8'h20}; // "SINE "
            endcase
        end
    endfunction

    // Function to extract individual byte from type_string
    function [7:0] type_byte;
        input [39:0] str;
        input [2:0]  idx;  // 0-4
        begin
            case (idx)
                3'd0: type_byte = str[39:32];
                3'd1: type_byte = str[31:24];
                3'd2: type_byte = str[23:16];
                3'd3: type_byte = str[15:8];
                3'd4: type_byte = str[7:0];
            endcase
        end
    endfunction

    //=========================================================================
    // Pre-compute type strings
    //=========================================================================
    wire [39:0] type_str_ch1 = type_string(type_ch1);
    wire [39:0] type_str_ch2 = type_string(type_ch2);

    //=========================================================================
    // Extract decimal digits from frequency (16-bit, 0-65535)
    //=========================================================================
    wire [3:0] f1_d5 = (freq_ch1 / 16'd10000) % 4'd10;
    wire [3:0] f1_d4 = (freq_ch1 / 16'd1000)  % 4'd10;
    wire [3:0] f1_d3 = (freq_ch1 / 16'd100)   % 4'd10;
    wire [3:0] f1_d2 = (freq_ch1 / 16'd10)    % 4'd10;
    wire [3:0] f1_d1 = (freq_ch1)             % 4'd10;

    wire [3:0] f2_d5 = (freq_ch2 / 16'd10000) % 4'd10;
    wire [3:0] f2_d4 = (freq_ch2 / 16'd1000)  % 4'd10;
    wire [3:0] f2_d3 = (freq_ch2 / 16'd100)   % 4'd10;
    wire [3:0] f2_d2 = (freq_ch2 / 16'd10)    % 4'd10;
    wire [3:0] f2_d1 = (freq_ch2)             % 4'd10;

    // Period digits (×100µs units, so divide by 10 to get ms)
    wire [3:0] p1_d4 = (period_ch1_x100us / 16'd1000) % 4'd10;  // ms
    wire [3:0] p1_d3 = (period_ch1_x100us / 16'd100)  % 4'd10;
    wire [3:0] p1_d2 = (period_ch1_x100us / 16'd10)   % 4'd10;
    wire [3:0] p1_d1 = (period_ch1_x100us)            % 4'd10;

    wire [3:0] p2_d4 = (period_ch2_x100us / 16'd1000) % 4'd10;
    wire [3:0] p2_d3 = (period_ch2_x100us / 16'd100)  % 4'd10;
    wire [3:0] p2_d2 = (period_ch2_x100us / 16'd10)   % 4'd10;
    wire [3:0] p2_d1 = (period_ch2_x100us)            % 4'd10;

    // Vpp digits — calibrated mV (16-bit)
    wire [3:0] vpp1_d4 = (vpp_mv_ch1 / 16'd1000) % 4'd10;
    wire [3:0] vpp1_d3 = (vpp_mv_ch1 / 16'd100)  % 4'd10;
    wire [3:0] vpp1_d2 = (vpp_mv_ch1 / 16'd10)   % 4'd10;
    wire [3:0] vpp1_d1 = (vpp_mv_ch1)            % 4'd10;

    wire [3:0] vpp2_d4 = (vpp_mv_ch2 / 16'd1000) % 4'd10;
    wire [3:0] vpp2_d3 = (vpp_mv_ch2 / 16'd100)  % 4'd10;
    wire [3:0] vpp2_d2 = (vpp_mv_ch2 / 16'd10)   % 4'd10;
    wire [3:0] vpp2_d1 = (vpp_mv_ch2)            % 4'd10;

    // Duty cycle digits (0-100%)
    wire [3:0] d1_d3 = (duty_ch1 / 7'd100) % 4'd10;
    wire [3:0] d1_d2 = (duty_ch1 / 7'd10)  % 4'd10;
    wire [3:0] d1_d1 = (duty_ch1)          % 4'd10;

    wire [3:0] d2_d3 = (duty_ch2 / 7'd100) % 4'd10;
    wire [3:0] d2_d2 = (duty_ch2 / 7'd10)  % 4'd10;
    wire [3:0] d2_d1 = (duty_ch2)          % 4'd10;

    // RMS digits — calibrated mV (3 digits max)
    wire [3:0] rms1_d3 = (rms_mv_ch1 / 16'd100) % 4'd10;
    wire [3:0] rms1_d2 = (rms_mv_ch1 / 16'd10)  % 4'd10;
    wire [3:0] rms1_d1 = (rms_mv_ch1)           % 4'd10;

    wire [3:0] rms2_d3 = (rms_mv_ch2 / 16'd100) % 4'd10;
    wire [3:0] rms2_d2 = (rms_mv_ch2 / 16'd10)  % 4'd10;
    wire [3:0] rms2_d1 = (rms_mv_ch2)           % 4'd10;

    // Average digits — calibrated mV
    wire [3:0] avg1_d3 = (avg_mv_ch1 / 16'd100) % 4'd10;
    wire [3:0] avg1_d2 = (avg_mv_ch1 / 16'd10)  % 4'd10;
    wire [3:0] avg1_d1 = (avg_mv_ch1)           % 4'd10;

    wire [3:0] avg2_d3 = (avg_mv_ch2 / 16'd100) % 4'd10;
    wire [3:0] avg2_d2 = (avg_mv_ch2 / 16'd10)  % 4'd10;
    wire [3:0] avg2_d1 = (avg_mv_ch2)           % 4'd10;

    // Max digits — calibrated mV
    wire [3:0] max1_d3 = (max_mv_ch1 / 16'd100) % 4'd10;
    wire [3:0] max1_d2 = (max_mv_ch1 / 16'd10)  % 4'd10;
    wire [3:0] max1_d1 = (max_mv_ch1)           % 4'd10;

    wire [3:0] max2_d3 = (max_mv_ch2 / 16'd100) % 4'd10;
    wire [3:0] max2_d2 = (max_mv_ch2 / 16'd10)  % 4'd10;
    wire [3:0] max2_d1 = (max_mv_ch2)           % 4'd10;

    // Vmin digits — calibrated mV
    wire [3:0] vmin1_d3 = (vmin_mv_ch1 / 16'd100) % 4'd10;
    wire [3:0] vmin1_d2 = (vmin_mv_ch1 / 16'd10)  % 4'd10;
    wire [3:0] vmin1_d1 = (vmin_mv_ch1)           % 4'd10;

    wire [3:0] vmin2_d3 = (vmin_mv_ch2 / 16'd100) % 4'd10;
    wire [3:0] vmin2_d2 = (vmin_mv_ch2 / 16'd10)  % 4'd10;
    wire [3:0] vmin2_d1 = (vmin_mv_ch2)           % 4'd10;

    // Crest factor digits (×100, so 141 means 1.41)
    wire [3:0] cf1_d4 = (crest_ch1_x100 / 11'd1000) % 4'd10;
    wire [3:0] cf1_d3 = (crest_ch1_x100 / 11'd100)  % 4'd10;
    wire [3:0] cf1_d2 = (crest_ch1_x100 / 11'd10)   % 4'd10;
    wire [3:0] cf1_d1 = (crest_ch1_x100)            % 4'd10;

    wire [3:0] cf2_d4 = (crest_ch2_x100 / 11'd1000) % 4'd10;
    wire [3:0] cf2_d3 = (crest_ch2_x100 / 11'd100)  % 4'd10;
    wire [3:0] cf2_d2 = (crest_ch2_x100 / 11'd10)   % 4'd10;
    wire [3:0] cf2_d1 = (crest_ch2_x100)            % 4'd10;

    // Rise time digits (0-255 µs)
    wire [3:0] rt1_d3 = (rise_time_ch1 / 8'd100) % 4'd10;
    wire [3:0] rt1_d2 = (rise_time_ch1 / 8'd10)  % 4'd10;
    wire [3:0] rt1_d1 = (rise_time_ch1)          % 4'd10;

    wire [3:0] rt2_d3 = (rise_time_ch2 / 8'd100) % 4'd10;
    wire [3:0] rt2_d2 = (rise_time_ch2 / 8'd10)  % 4'd10;
    wire [3:0] rt2_d1 = (rise_time_ch2)          % 4'd10;

    // Sample rate digits
    wire [3:0] srate_d5 = (sample_rate_hz / 16'd10000) % 4'd10;
    wire [3:0] srate_d4 = (sample_rate_hz / 16'd1000)  % 4'd10;
    wire [3:0] srate_d3 = (sample_rate_hz / 16'd100)   % 4'd10;
    wire [3:0] srate_d2 = (sample_rate_hz / 16'd10)    % 4'd10;
    wire [3:0] srate_d1 = (sample_rate_hz)             % 4'd10;

    // Trigger level in mV
    wire [15:0] trigger_mv = (({8'b0, trigger_level} * 16'd4000) + 16'd512) >> 10;
    wire [3:0]  trig_d3 = (trigger_mv / 16'd100) % 4'd10;
    wire [3:0]  trig_d2 = (trigger_mv / 16'd10)  % 4'd10;
    wire [3:0]  trig_d1 = (trigger_mv)           % 4'd10;

    //=========================================================================
    // Character selection mux — pick the right char for current (x,y) in metrics
    //
    // Layout (6 rows):
    //   Row 0: "CH1 F:##### T:####us Vpp:####mV D:##% W:XXXXX"
    //   Row 1: "    Vrms:### Vavg:### Vmax:### Vmin:###mV    "
    //   Row 2: "CH2 F:##### T:####us Vpp:####mV D:##% W:XXXXX"
    //   Row 3: "    Vrms:### Vavg:### Vmax:### Vmin:###mV    "
    //   Row 4: "CF1:#### CF2:#### RT1:## RT2:##us            "
    //   Row 5: "ADC:#####k TRG:###mV STA:XXXXX               "
    //=========================================================================

    reg [7:0] metrics_char;

    always @(*) begin
        metrics_char = 8'h20;  // default: space

        case (char_cell_y)
            //=============================================================
            // Row 0: CH1 F:##### T:####us Vpp:####mV D:##% W:XXXXX
            //=============================================================
            3'd0: begin
                case (char_cell_x)
                    7'd0:  metrics_char = 8'h43;  // 'C'
                    7'd1:  metrics_char = 8'h48;  // 'H'
                    7'd2:  metrics_char = 8'h31;  // '1'
                    7'd3:  metrics_char = 8'h20;  // space
                    7'd4:  metrics_char = 8'h46;  // 'F'
                    7'd5:  metrics_char = 8'h3A;  // ':'
                    7'd6:  metrics_char = digit_to_ascii(f1_d5);
                    7'd7:  metrics_char = digit_to_ascii(f1_d4);
                    7'd8:  metrics_char = digit_to_ascii(f1_d3);
                    7'd9:  metrics_char = digit_to_ascii(f1_d2);
                    7'd10: metrics_char = digit_to_ascii(f1_d1);
                    7'd11: metrics_char = 8'h48;  // 'H' for Hz
                    7'd12: metrics_char = 8'h7A;  // 'z'
                    7'd13: metrics_char = 8'h20;  // space
                    7'd14: metrics_char = 8'h54;  // 'T'
                    7'd15: metrics_char = 8'h3A;  // ':'
                    7'd16: metrics_char = digit_to_ascii(p1_d4);
                    7'd17: metrics_char = digit_to_ascii(p1_d3);
                    7'd18: metrics_char = digit_to_ascii(p1_d2);
                    7'd19: metrics_char = digit_to_ascii(p1_d1);
                    7'd20: metrics_char = 8'h75;  // 'u'
                    7'd21: metrics_char = 8'h73;  // 's'
                    7'd22: metrics_char = 8'h20;  // space
                    7'd23: metrics_char = 8'h56;  // 'V'
                    7'd24: metrics_char = digit_to_ascii(vpp1_d4);
                    7'd25: metrics_char = digit_to_ascii(vpp1_d3);
                    7'd26: metrics_char = digit_to_ascii(vpp1_d2);
                    7'd27: metrics_char = digit_to_ascii(vpp1_d1);
                    7'd28: metrics_char = 8'h6D;  // 'm'
                    7'd29: metrics_char = 8'h56;  // 'V'
                    7'd30: metrics_char = 8'h20;  // space
                    7'd31: metrics_char = 8'h44;  // 'D'
                    7'd32: metrics_char = 8'h3A;  // ':'
                    7'd33: metrics_char = digit_to_ascii(d1_d3);
                    7'd34: metrics_char = digit_to_ascii(d1_d2);
                    7'd35: metrics_char = digit_to_ascii(d1_d1);
                    7'd36: metrics_char = 8'h25;  // '%'
                    7'd37: metrics_char = 8'h20;  // space
                    7'd38: metrics_char = 8'h57;  // 'W'
                    7'd39: metrics_char = 8'h3A;  // ':'
                    7'd40: metrics_char = type_byte(type_str_ch1, 3'd0);
                    7'd41: metrics_char = type_byte(type_str_ch1, 3'd1);
                    7'd42: metrics_char = type_byte(type_str_ch1, 3'd2);
                    7'd43: metrics_char = type_byte(type_str_ch1, 3'd3);
                    7'd44: metrics_char = type_byte(type_str_ch1, 3'd4);
                    default: metrics_char = 8'h20;
                endcase
            end

            //=============================================================
            // Row 1: CH1 Vrms:### Vavg:### Vmax:### Vmin:###mV
            //=============================================================
            3'd1: begin
                case (char_cell_x)
                    7'd0:  metrics_char = 8'h20;  // indent
                    7'd1:  metrics_char = 8'h20;  // indent
                    7'd2:  metrics_char = 8'h20;  // indent
                    7'd3:  metrics_char = 8'h20;  // indent
                    7'd4:  metrics_char = 8'h56;  // 'V'
                    7'd5:  metrics_char = 8'h72;  // 'r'
                    7'd6:  metrics_char = 8'h6D;  // 'm'
                    7'd7:  metrics_char = 8'h73;  // 's'
                    7'd8:  metrics_char = 8'h3A;  // ':'
                    7'd9:  metrics_char = digit_to_ascii(rms1_d3);
                    7'd10: metrics_char = digit_to_ascii(rms1_d2);
                    7'd11: metrics_char = digit_to_ascii(rms1_d1);
                    7'd12: metrics_char = 8'h20;  // space
                    7'd13: metrics_char = 8'h56;  // 'V'
                    7'd14: metrics_char = 8'h61;  // 'a'
                    7'd15: metrics_char = 8'h76;  // 'v'
                    7'd16: metrics_char = 8'h67;  // 'g'
                    7'd17: metrics_char = 8'h3A;  // ':'
                    7'd18: metrics_char = digit_to_ascii(avg1_d3);
                    7'd19: metrics_char = digit_to_ascii(avg1_d2);
                    7'd20: metrics_char = digit_to_ascii(avg1_d1);
                    7'd21: metrics_char = 8'h20;  // space
                    7'd22: metrics_char = 8'h56;  // 'V'
                    7'd23: metrics_char = 8'h6D;  // 'm'
                    7'd24: metrics_char = 8'h61;  // 'a'
                    7'd25: metrics_char = 8'h78;  // 'x'
                    7'd26: metrics_char = 8'h3A;  // ':'
                    7'd27: metrics_char = digit_to_ascii(max1_d3);
                    7'd28: metrics_char = digit_to_ascii(max1_d2);
                    7'd29: metrics_char = digit_to_ascii(max1_d1);
                    7'd30: metrics_char = 8'h20;  // space
                    7'd31: metrics_char = 8'h56;  // 'V'
                    7'd32: metrics_char = 8'h6D;  // 'm'
                    7'd33: metrics_char = 8'h69;  // 'i'
                    7'd34: metrics_char = 8'h6E;  // 'n'
                    7'd35: metrics_char = 8'h3A;  // ':'
                    7'd36: metrics_char = digit_to_ascii(vmin1_d3);
                    7'd37: metrics_char = digit_to_ascii(vmin1_d2);
                    7'd38: metrics_char = digit_to_ascii(vmin1_d1);
                    7'd39: metrics_char = 8'h6D;  // 'm'
                    7'd40: metrics_char = 8'h56;  // 'V'
                    default: metrics_char = 8'h20;
                endcase
            end

            //=============================================================
            // Row 2: CH2 F:##### T:####us Vpp:####mV D:##% W:XXXXX
            //=============================================================
            3'd2: begin
                case (char_cell_x)
                    7'd0:  metrics_char = 8'h43;  // 'C'
                    7'd1:  metrics_char = 8'h48;  // 'H'
                    7'd2:  metrics_char = 8'h32;  // '2'
                    7'd3:  metrics_char = 8'h20;  // space
                    7'd4:  metrics_char = 8'h46;  // 'F'
                    7'd5:  metrics_char = 8'h3A;  // ':'
                    7'd6:  metrics_char = digit_to_ascii(f2_d5);
                    7'd7:  metrics_char = digit_to_ascii(f2_d4);
                    7'd8:  metrics_char = digit_to_ascii(f2_d3);
                    7'd9:  metrics_char = digit_to_ascii(f2_d2);
                    7'd10: metrics_char = digit_to_ascii(f2_d1);
                    7'd11: metrics_char = 8'h48;  // 'H'
                    7'd12: metrics_char = 8'h7A;  // 'z'
                    7'd13: metrics_char = 8'h20;  // space
                    7'd14: metrics_char = 8'h54;  // 'T'
                    7'd15: metrics_char = 8'h3A;  // ':'
                    7'd16: metrics_char = digit_to_ascii(p2_d4);
                    7'd17: metrics_char = digit_to_ascii(p2_d3);
                    7'd18: metrics_char = digit_to_ascii(p2_d2);
                    7'd19: metrics_char = digit_to_ascii(p2_d1);
                    7'd20: metrics_char = 8'h75;  // 'u'
                    7'd21: metrics_char = 8'h73;  // 's'
                    7'd22: metrics_char = 8'h20;  // space
                    7'd23: metrics_char = 8'h56;  // 'V'
                    7'd24: metrics_char = digit_to_ascii(vpp2_d4);
                    7'd25: metrics_char = digit_to_ascii(vpp2_d3);
                    7'd26: metrics_char = digit_to_ascii(vpp2_d2);
                    7'd27: metrics_char = digit_to_ascii(vpp2_d1);
                    7'd28: metrics_char = 8'h6D;  // 'm'
                    7'd29: metrics_char = 8'h56;  // 'V'
                    7'd30: metrics_char = 8'h20;  // space
                    7'd31: metrics_char = 8'h44;  // 'D'
                    7'd32: metrics_char = 8'h3A;  // ':'
                    7'd33: metrics_char = digit_to_ascii(d2_d3);
                    7'd34: metrics_char = digit_to_ascii(d2_d2);
                    7'd35: metrics_char = digit_to_ascii(d2_d1);
                    7'd36: metrics_char = 8'h25;  // '%'
                    7'd37: metrics_char = 8'h20;  // space
                    7'd38: metrics_char = 8'h57;  // 'W'
                    7'd39: metrics_char = 8'h3A;  // ':'
                    7'd40: metrics_char = type_byte(type_str_ch2, 3'd0);
                    7'd41: metrics_char = type_byte(type_str_ch2, 3'd1);
                    7'd42: metrics_char = type_byte(type_str_ch2, 3'd2);
                    7'd43: metrics_char = type_byte(type_str_ch2, 3'd3);
                    7'd44: metrics_char = type_byte(type_str_ch2, 3'd4);
                    default: metrics_char = 8'h20;
                endcase
            end

            //=============================================================
            // Row 3: CH2 Vrms:### Vavg:### Vmax:### Vmin:###mV
            //=============================================================
            3'd3: begin
                case (char_cell_x)
                    7'd0:  metrics_char = 8'h20;
                    7'd1:  metrics_char = 8'h20;
                    7'd2:  metrics_char = 8'h20;
                    7'd3:  metrics_char = 8'h20;
                    7'd4:  metrics_char = 8'h56;  // 'V'
                    7'd5:  metrics_char = 8'h72;  // 'r'
                    7'd6:  metrics_char = 8'h6D;  // 'm'
                    7'd7:  metrics_char = 8'h73;  // 's'
                    7'd8:  metrics_char = 8'h3A;  // ':'
                    7'd9:  metrics_char = digit_to_ascii(rms2_d3);
                    7'd10: metrics_char = digit_to_ascii(rms2_d2);
                    7'd11: metrics_char = digit_to_ascii(rms2_d1);
                    7'd12: metrics_char = 8'h20;
                    7'd13: metrics_char = 8'h56;  // 'V'
                    7'd14: metrics_char = 8'h61;  // 'a'
                    7'd15: metrics_char = 8'h76;  // 'v'
                    7'd16: metrics_char = 8'h67;  // 'g'
                    7'd17: metrics_char = 8'h3A;  // ':'
                    7'd18: metrics_char = digit_to_ascii(avg2_d3);
                    7'd19: metrics_char = digit_to_ascii(avg2_d2);
                    7'd20: metrics_char = digit_to_ascii(avg2_d1);
                    7'd21: metrics_char = 8'h20;
                    7'd22: metrics_char = 8'h56;  // 'V'
                    7'd23: metrics_char = 8'h6D;  // 'm'
                    7'd24: metrics_char = 8'h61;  // 'a'
                    7'd25: metrics_char = 8'h78;  // 'x'
                    7'd26: metrics_char = 8'h3A;  // ':'
                    7'd27: metrics_char = digit_to_ascii(max2_d3);
                    7'd28: metrics_char = digit_to_ascii(max2_d2);
                    7'd29: metrics_char = digit_to_ascii(max2_d1);
                    7'd30: metrics_char = 8'h20;
                    7'd31: metrics_char = 8'h56;  // 'V'
                    7'd32: metrics_char = 8'h6D;  // 'm'
                    7'd33: metrics_char = 8'h69;  // 'i'
                    7'd34: metrics_char = 8'h6E;  // 'n'
                    7'd35: metrics_char = 8'h3A;  // ':'
                    7'd36: metrics_char = digit_to_ascii(vmin2_d3);
                    7'd37: metrics_char = digit_to_ascii(vmin2_d2);
                    7'd38: metrics_char = digit_to_ascii(vmin2_d1);
                    7'd39: metrics_char = 8'h6D;  // 'm'
                    7'd40: metrics_char = 8'h56;  // 'V'
                    default: metrics_char = 8'h20;
                endcase
            end

            //=============================================================
            // Row 4: CF1:#### CF2:#### RT1:## RT2:##us
            //=============================================================
            3'd4: begin
                case (char_cell_x)
                    7'd0:  metrics_char = 8'h43;  // 'C'
                    7'd1:  metrics_char = 8'h46;  // 'F'
                    7'd2:  metrics_char = 8'h31;  // '1'
                    7'd3:  metrics_char = 8'h3A;  // ':'
                    7'd4:  metrics_char = digit_to_ascii(cf1_d4);
                    7'd5:  metrics_char = digit_to_ascii(cf1_d3);
                    7'd6:  metrics_char = digit_to_ascii(cf1_d2);
                    7'd7:  metrics_char = 8'h2E;  // '.'
                    7'd8:  metrics_char = digit_to_ascii(cf1_d1);
                    7'd9:  metrics_char = 8'h20;  // space
                    7'd10: metrics_char = 8'h43;  // 'C'
                    7'd11: metrics_char = 8'h46;  // 'F'
                    7'd12: metrics_char = 8'h32;  // '2'
                    7'd13: metrics_char = 8'h3A;  // ':'
                    7'd14: metrics_char = digit_to_ascii(cf2_d4);
                    7'd15: metrics_char = digit_to_ascii(cf2_d3);
                    7'd16: metrics_char = digit_to_ascii(cf2_d2);
                    7'd17: metrics_char = 8'h2E;  // '.'
                    7'd18: metrics_char = digit_to_ascii(cf2_d1);
                    7'd19: metrics_char = 8'h20;  // space
                    7'd20: metrics_char = 8'h52;  // 'R'
                    7'd21: metrics_char = 8'h54;  // 'T'
                    7'd22: metrics_char = 8'h31;  // '1'
                    7'd23: metrics_char = 8'h3A;  // ':'
                    7'd24: metrics_char = digit_to_ascii(rt1_d3);
                    7'd25: metrics_char = digit_to_ascii(rt1_d2);
                    7'd26: metrics_char = digit_to_ascii(rt1_d1);
                    7'd27: metrics_char = 8'h20;  // space
                    7'd28: metrics_char = 8'h52;  // 'R'
                    7'd29: metrics_char = 8'h54;  // 'T'
                    7'd30: metrics_char = 8'h32;  // '2'
                    7'd31: metrics_char = 8'h3A;  // ':'
                    7'd32: metrics_char = digit_to_ascii(rt2_d3);
                    7'd33: metrics_char = digit_to_ascii(rt2_d2);
                    7'd34: metrics_char = digit_to_ascii(rt2_d1);
                    7'd35: metrics_char = 8'h75;  // 'u'
                    7'd36: metrics_char = 8'h73;  // 's'
                    default: metrics_char = 8'h20;
                endcase
            end

            //=============================================================
            // Row 5: ADC:#####k TRG:###mV STA:XXXXX
            //=============================================================
            3'd5: begin
                case (char_cell_x)
                    7'd0:  metrics_char = 8'h41;  // 'A'
                    7'd1:  metrics_char = 8'h44;  // 'D'
                    7'd2:  metrics_char = 8'h43;  // 'C'
                    7'd3:  metrics_char = 8'h3A;  // ':'
                    7'd4:  metrics_char = digit_to_ascii(srate_d5);
                    7'd5:  metrics_char = digit_to_ascii(srate_d4);
                    7'd6:  metrics_char = digit_to_ascii(srate_d3);
                    7'd7:  metrics_char = digit_to_ascii(srate_d2);
                    7'd8:  metrics_char = digit_to_ascii(srate_d1);
                    7'd9:  metrics_char = 8'h6B;  // 'k'
                    7'd10: metrics_char = 8'h53;  // 'S'
                    7'd11: metrics_char = 8'h2F;  // '/'
                    7'd12: metrics_char = 8'h73;  // 's'
                    7'd13: metrics_char = 8'h20;  // space
                    7'd14: metrics_char = 8'h54;  // 'T'
                    7'd15: metrics_char = 8'h52;  // 'R'
                    7'd16: metrics_char = 8'h47;  // 'G'
                    7'd17: metrics_char = 8'h3A;  // ':'
                    7'd18: metrics_char = digit_to_ascii(trig_d3);
                    7'd19: metrics_char = digit_to_ascii(trig_d2);
                    7'd20: metrics_char = digit_to_ascii(trig_d1);
                    7'd21: metrics_char = 8'h6D;  // 'm'
                    7'd22: metrics_char = 8'h56;  // 'V'
                    7'd23: metrics_char = 8'h20;  // space
                    7'd24: metrics_char = 8'h53;  // 'S'
                    7'd25: metrics_char = 8'h54;  // 'T'
                    7'd26: metrics_char = 8'h41;  // 'A'
                    7'd27: metrics_char = 8'h3A;  // ':'
                    7'd28: metrics_char = trigger_armed ? 8'h41 : 8'h57;  // 'A'/'W'
                    7'd29: metrics_char = trigger_armed ? 8'h52 : 8'h41;  // 'R'/'A'
                    7'd30: metrics_char = trigger_armed ? 8'h4D : 8'h49;  // 'M'/'I'
                    7'd31: metrics_char = trigger_armed ? 8'h45 : 8'h54;  // 'E'/'T'
                    7'd32: metrics_char = 8'h44;  // 'D'
                    default: metrics_char = 8'h20;
                endcase
            end

            default: metrics_char = 8'h20;
        endcase
    end

    //=========================================================================
    // Char gen instance for metrics text
    //=========================================================================
    wire char_pixel_on;

    char_gen u_char_gen (
        .clk(clk),
        .char_code(metrics_char),
        .char_row(char_row),
        .char_col(char_col),
        .pixel_on(char_pixel_on)
    );

    //=========================================================================
    // Main Display Output
    //=========================================================================
    always @(*) begin
        vga_r = 4'h0;
        vga_g = 4'h0;
        vga_b = 4'h0;

        if (de) begin
            //-----------------------------------------------------------------
            // Metrics Bar (y=432..479)
            //-----------------------------------------------------------------
            if (in_metrics_bar) begin
                // Dark background
                vga_r = 4'h1; vga_g = 4'h1; vga_b = 4'h1;

                // Separator line at top of metrics bar
                if (pixel_y == 432) begin
                    vga_r = 4'h8; vga_g = 4'h8; vga_b = 4'h8;
                end

                // Row background tints
                // CH1 rows: gold/yellow tint (rows 0-1)
                if (char_cell_y == 3'd0) begin
                    vga_r = 4'h2; vga_g = 4'h2; vga_b = 4'h0;
                end
                if (char_cell_y == 3'd1) begin
                    vga_r = 4'h1; vga_g = 4'h1; vga_b = 4'h0;
                end
                // CH2 rows: cyan/blue tint (rows 2-3)
                if (char_cell_y == 3'd2) begin
                    vga_r = 4'h0; vga_g = 4'h1; vga_b = 4'h2;
                end
                if (char_cell_y == 3'd3) begin
                    vga_r = 4'h0; vga_g = 4'h1; vga_b = 4'h1;
                end
                // CF/RT row: purple-ish tint (row 4)
                if (char_cell_y == 3'd4) begin
                    vga_r = 4'h1; vga_g = 4'h0; vga_b = 4'h1;
                end
                // ADC/TRG row: greenish + orange tint (row 5)
                if (char_cell_y == 3'd5) begin
                    vga_r = 4'h1; vga_g = 4'h2; vga_b = 4'h0;
                end

                // Group separators
                if (pixel_y == 448) begin
                    vga_r = 4'h4; vga_g = 4'h4; vga_b = 4'h4;
                end
                if (pixel_y == 464) begin
                    vga_r = 4'h3; vga_g = 4'h3; vga_b = 4'h3;
                end

                // Character pixels
                if (char_pixel_on) begin
                    // CH1 text: bright yellow (rows 0-1)
                    if (char_cell_y <= 3'd1) begin
                        vga_r = 4'hF; vga_g = 4'hF; vga_b = 4'h0;
                    // CH2 text: bright cyan (rows 2-3)
                    end else if (char_cell_y <= 3'd3) begin
                        vga_r = 4'h0; vga_g = 4'hF; vga_b = 4'hF;
                    // CF/RT row: magenta (row 4)
                    end else if (char_cell_y == 3'd4) begin
                        vga_r = 4'hF; vga_g = 4'h8; vga_b = 4'hF;
                    // ADC/TRG row: green (row 5)
                    end else begin
                        vga_r = 4'h0; vga_g = 4'hF; vga_b = 4'h0;
                    end
                end
            end
            //-----------------------------------------------------------------
            // Waveform Area (y=0..431) — Professional Oscilloscope Graticule
            //-----------------------------------------------------------------
            else begin
                // Major grid lines (darker for better contrast)
                if (major_grid_x) begin
                    vga_r = 4'h1; vga_g = 4'h2; vga_b = 4'h1;
                end
                if (major_grid_y) begin
                    vga_r = 4'h1; vga_g = 4'h2; vga_b = 4'h1;
                end

                // Minor grid dots (very faint, sub-division markers)
                if ((pixel_x % 10) == 0 && (pixel_y % 9) == 0 && !major_grid_x && !major_grid_y) begin
                    vga_r = 4'h1; vga_g = 4'h1; vga_b = 4'h0;
                end

                // Center crosshair (brighter)
                if (center_line_x) begin
                    vga_r = 4'h3; vga_g = 4'h4; vga_b = 4'h3;
                end
                if (center_line_y) begin
                    vga_r = 4'h3; vga_g = 4'h4; vga_b = 4'h3;
                end
                // Center dot is brighter
                if (center_line_x && center_line_y) begin
                    vga_r = 4'h4; vga_g = 4'h6; vga_b = 4'h4;
                end

                // CH1 waveform — yellow
                if (hit_ch1) begin
                    vga_r = 4'hF; vga_g = 4'hF; vga_b = 4'h0;
                end

                // CH2 waveform — blue
                if (hit_ch2) begin
                    vga_r = 4'h0; vga_g = 4'h6; vga_b = 4'hF;
                end

                // Overlap — bright white
                if (hit_ch1 && hit_ch2) begin
                    vga_r = 4'hF; vga_g = 4'hF; vga_b = 4'hF;
                end

                // Clipping indicators — flash red at extremes
                if ((clip_ch1_high || clip_ch1_low) && !hit_ch2) begin
                    vga_r = 4'hF; vga_g = 4'h2; vga_b = 4'h0;  // orange-red
                end
                if ((clip_ch2_high || clip_ch2_low) && !hit_ch1) begin
                    vga_r = 4'hF; vga_g = 4'h2; vga_b = 4'h4;  // pink
                end
            end
        end
    end

endmodule
