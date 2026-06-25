`timescale 1ns / 1ps
//=============================================================================
// Waveform Display Module
// Dual-channel oscilloscope display with grid, traces, and metrics overlay.
// Integrates char_gen for on-screen text (frequency, Vpp, RMS, Avg, Max, type).
//
// Metrics bar (y=432-479, 48 rows, 6 char rows of 8px each):
//   Row 0: CH1  F:#####Hz  V:####mV  T:X
//   Row 1:      R:###  A:###  M:###   (mV)
//   Row 2: CH2  F:#####Hz  V:####mV  T:X
//   Row 3:      R:###  A:###  M:###   (mV)
//   Row 4: ADC:#####kS/s  (sample rate)
//   Row 5: TRG:###mV STA:XXXXX (trigger mV + armed/wait)
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
    // Metrics — frequency, Vpp, type (raw counts, backward compatible)
    input  wire [15:0]   freq_ch1,
    input  wire [7:0]    vpp_ch1,
    input  wire [1:0]    type_ch1,
    input  wire [15:0]   freq_ch2,
    input  wire [7:0]    vpp_ch2,
    input  wire [1:0]    type_ch2,
    input  wire          meas_valid,
    // Metrics — RMS, Average, Max (raw counts, backward compatible)
    input  wire [7:0]    rms_ch1,
    input  wire [7:0]    avg_ch1,
    input  wire [7:0]    max_ch1,
    input  wire [7:0]    rms_ch2,
    input  wire [7:0]    avg_ch2,
    input  wire [7:0]    max_ch2,
    // Calibrated voltage outputs (mV)
    input  wire [15:0]   vpp_mv_ch1,
    input  wire [15:0]   rms_mv_ch1,
    input  wire [15:0]   avg_mv_ch1,
    input  wire [15:0]   max_mv_ch1,
    input  wire [15:0]   vpp_mv_ch2,
    input  wire [15:0]   rms_mv_ch2,
    input  wire [15:0]   avg_mv_ch2,
    input  wire [15:0]   max_mv_ch2,
    // Sample rate (debug / calibration)
    input  wire [15:0]   sample_rate_hz,
    // Trigger status
    input  wire          trigger_armed,
    input  wire [7:0]    trigger_level,
    // VGA output
    output reg  [3:0]    vga_r,
    output reg  [3:0]    vga_g,
    output reg  [3:0]    vga_b
);

//=============================================================================
// ADC value -> Y coordinate (mapped to waveform area: 0->431)
// Metrics bar occupies y=432..479, so waveform must fit in y=0..431.
//=============================================================================
wire [9:0] wave_y_ch1 = 10'd431 - ((wave_ch1 * 10'd431) >> 8);
wire [9:0] wave_y_ch2 = 10'd431 - ((wave_ch2 * 10'd431) >> 8);

//=============================================================================
// Grid & Center Lines
//=============================================================================
wire grid_x  = ((pixel_x % 80) == 0);
wire grid_y  = ((pixel_y % 60) == 0);
wire center_line = (pixel_y == 215);  // center of waveform area (431/2)

//=============================================================================
// Waveform hit detection (3-pixel wide traces, clamped to waveform area)
//=============================================================================
wire hit_ch1 = (pixel_y >= ((wave_y_ch1 > 1) ? wave_y_ch1 - 1 : 0)) &&
               (pixel_y <= ((wave_y_ch1 < 430) ? wave_y_ch1 + 1 : 431));
wire hit_ch2 = (pixel_y >= ((wave_y_ch2 > 1) ? wave_y_ch2 - 1 : 0)) &&
               (pixel_y <= ((wave_y_ch2 < 430) ? wave_y_ch2 + 1 : 431));

//=============================================================================
// Metrics Bar Area (pixels y=432..479, 48 rows = 6 char rows)
//=============================================================================
wire in_metrics_bar = (pixel_y >= 432);

//=============================================================================
// Character Generator addressing
//=============================================================================
wire [2:0] char_col = pixel_x[2:0];
wire [2:0] char_row_offset = (pixel_y - 10'd432);
wire [2:0] char_row = char_row_offset[2:0];  // row within 8x8 character (0-7)

// Which character cell column (0-79 for 640px / 8)
wire [6:0] char_cell_x = pixel_x[9:3];
wire [2:0] char_cell_y = (pixel_y - 10'd432) >> 3;  // which char row in metrics (0-5)

//=============================================================================
// Convert BCD digits to ASCII
//=============================================================================
function [7:0] digit_to_ascii;
    input [3:0] digit;
    begin
        digit_to_ascii = {4'h3, digit};  // '0' = 0x30
    end
endfunction

//=============================================================================
// Extract decimal digits from frequency (16-bit, 0-65535)
//=============================================================================
wire [3:0] freq1_d5 = (freq_ch1 / 16'd10000) % 4'd10;  // 10kHz
wire [3:0] freq1_d4 = (freq_ch1 / 16'd1000)  % 4'd10;  // 1kHz
wire [3:0] freq1_d3 = (freq_ch1 / 16'd100)   % 4'd10;  // 100Hz
wire [3:0] freq1_d2 = (freq_ch1 / 16'd10)    % 4'd10;  // 10Hz
wire [3:0] freq1_d1 = (freq_ch1)             % 4'd10;  // 1Hz

wire [3:0] freq2_d5 = (freq_ch2 / 16'd10000) % 4'd10;
wire [3:0] freq2_d4 = (freq_ch2 / 16'd1000)  % 4'd10;
wire [3:0] freq2_d3 = (freq_ch2 / 16'd100)   % 4'd10;
wire [3:0] freq2_d2 = (freq_ch2 / 16'd10)    % 4'd10;
wire [3:0] freq2_d1 = (freq_ch2)             % 4'd10;

// Vpp digits — calibrated mV (16-bit, 0-65535, practical max ~1000mV)
wire [3:0] vpp1_mv_d4 = (vpp_mv_ch1 / 16'd1000) % 4'd10;  // 1000mV
wire [3:0] vpp1_mv_d3 = (vpp_mv_ch1 / 16'd100)  % 4'd10;  // 100mV
wire [3:0] vpp1_mv_d2 = (vpp_mv_ch1 / 16'd10)   % 4'd10;  // 10mV
wire [3:0] vpp1_mv_d1 = (vpp_mv_ch1)            % 4'd10;  // 1mV

wire [3:0] vpp2_mv_d4 = (vpp_mv_ch2 / 16'd1000) % 4'd10;
wire [3:0] vpp2_mv_d3 = (vpp_mv_ch2 / 16'd100)  % 4'd10;
wire [3:0] vpp2_mv_d2 = (vpp_mv_ch2 / 16'd10)   % 4'd10;
wire [3:0] vpp2_mv_d1 = (vpp_mv_ch2)            % 4'd10;

// RMS digits — calibrated mV (16-bit, 0-500mV typical)
wire [3:0] rms1_mv_d3 = (rms_mv_ch1 / 16'd100) % 4'd10;
wire [3:0] rms1_mv_d2 = (rms_mv_ch1 / 16'd10)  % 4'd10;
wire [3:0] rms1_mv_d1 = (rms_mv_ch1)           % 4'd10;

wire [3:0] rms2_mv_d3 = (rms_mv_ch2 / 16'd100) % 4'd10;
wire [3:0] rms2_mv_d2 = (rms_mv_ch2 / 16'd10)  % 4'd10;
wire [3:0] rms2_mv_d1 = (rms_mv_ch2)           % 4'd10;

// Average digits — calibrated mV (16-bit, 0-1000mV typical for DC offset)
wire [3:0] avg1_mv_d3 = (avg_mv_ch1 / 16'd100) % 4'd10;
wire [3:0] avg1_mv_d2 = (avg_mv_ch1 / 16'd10)  % 4'd10;
wire [3:0] avg1_mv_d1 = (avg_mv_ch1)           % 4'd10;

wire [3:0] avg2_mv_d3 = (avg_mv_ch2 / 16'd100) % 4'd10;
wire [3:0] avg2_mv_d2 = (avg_mv_ch2 / 16'd10)  % 4'd10;
wire [3:0] avg2_mv_d1 = (avg_mv_ch2)           % 4'd10;

// Max digits — calibrated mV (16-bit, 0-1000mV)
wire [3:0] max1_mv_d3 = (max_mv_ch1 / 16'd100) % 4'd10;
wire [3:0] max1_mv_d2 = (max_mv_ch1 / 16'd10)  % 4'd10;
wire [3:0] max1_mv_d1 = (max_mv_ch1)           % 4'd10;

wire [3:0] max2_mv_d3 = (max_mv_ch2 / 16'd100) % 4'd10;
wire [3:0] max2_mv_d2 = (max_mv_ch2 / 16'd10)  % 4'd10;
wire [3:0] max2_mv_d1 = (max_mv_ch2)           % 4'd10;

// Sample rate digits (16-bit, 0-65535) — display as kS/s
wire [3:0] srate_d5 = (sample_rate_hz / 16'd10000) % 4'd10;
wire [3:0] srate_d4 = (sample_rate_hz / 16'd1000)  % 4'd10;
wire [3:0] srate_d3 = (sample_rate_hz / 16'd100)   % 4'd10;
wire [3:0] srate_d2 = (sample_rate_hz / 16'd10)    % 4'd10;
wire [3:0] srate_d1 = (sample_rate_hz)             % 4'd10;

// Trigger level in mV (CAL_MV_X1024=4000, 3.90625mV/LSB, range 0-996mV)
// trigger_mv = round(trigger_level * 4000 / 1024)
wire [15:0] trigger_mv = (({8'b0, trigger_level} * 16'd4000) + 16'd512) >> 10;
wire [3:0]  trig_mv_d3 = (trigger_mv / 16'd100) % 4'd10;
wire [3:0]  trig_mv_d2 = (trigger_mv / 16'd10)  % 4'd10;
wire [3:0]  trig_mv_d1 = (trigger_mv)           % 4'd10;

//=============================================================================
// Character selection mux: pick the right char for current (x,y) in metrics
//=============================================================================
// Layout (6 rows):
//   Row 0 (y=432-439): "CH1: F:#####Hz  V:####mV  T:X"
//   Row 1 (y=440-447): "      R:###  A:###  M:###  mV"
//   Row 2 (y=448-455): "CH2: F:#####Hz  V:####mV  T:X"
//   Row 3 (y=456-463): "      R:###  A:###  M:###  mV"
//   Row 4 (y=464-471): "ADC:#####kS/s"
//   Row 5 (y=472-479): "TRG:### MODE:XXXXX" (trigger status)

// Waveform type character: 'Q'=sQuare, 'T'=Triangle, 'N'=siNe
function [7:0] type_char;
    input [1:0] t;
    begin
        case (t)
            2'b01: type_char = 8'h51;   // 'Q' — sQuare
            2'b10: type_char = 8'h54;   // 'T' — Triangle
            default: type_char = 8'h4E; // 'N' — siNe
        endcase
    end
endfunction

reg [7:0] metrics_char;

always @(*) begin
    metrics_char = 8'h20;  // default: space

    case (char_cell_y)
        //=================================================================
        // Row 0: CH1 F:#####Hz  V:####mV  T:X
        //=================================================================
        3'd0: begin
            case (char_cell_x)
                7'd0:  metrics_char = 8'h43;  // 'C'
                7'd1:  metrics_char = 8'h48;  // 'H'
                7'd2:  metrics_char = 8'h31;  // '1'
                7'd3:  metrics_char = 8'h3A;  // ':'
                7'd4:  metrics_char = 8'h46;  // 'F'
                7'd5:  metrics_char = digit_to_ascii(freq1_d5);
                7'd6:  metrics_char = digit_to_ascii(freq1_d4);
                7'd7:  metrics_char = digit_to_ascii(freq1_d3);
                7'd8:  metrics_char = digit_to_ascii(freq1_d2);
                7'd9:  metrics_char = digit_to_ascii(freq1_d1);
                7'd10: metrics_char = 8'h48;  // 'H'
                7'd11: metrics_char = 8'h7A;  // 'z' (Hz)
                7'd12: metrics_char = 8'h20;  // space
                7'd13: metrics_char = 8'h56;  // 'V'
                7'd14: metrics_char = digit_to_ascii(vpp1_mv_d4);
                7'd15: metrics_char = digit_to_ascii(vpp1_mv_d3);
                7'd16: metrics_char = digit_to_ascii(vpp1_mv_d2);
                7'd17: metrics_char = digit_to_ascii(vpp1_mv_d1);
                7'd18: metrics_char = 8'h6D;  // 'm'
                7'd19: metrics_char = 8'h56;  // 'V'
                7'd20: metrics_char = 8'h20;  // space
                7'd21: metrics_char = 8'h54;  // 'T'
                7'd22: metrics_char = 8'h3A;  // ':'
                7'd23: metrics_char = type_char(type_ch1);
                default: metrics_char = 8'h20;
            endcase
        end

        //=================================================================
        // Row 1: CH1  R:###  A:###  M:###  mV
        //=================================================================
        3'd1: begin
            case (char_cell_x)
                7'd0:  metrics_char = 8'h20;  // space (indent)
                7'd1:  metrics_char = 8'h52;  // 'R'
                7'd2:  metrics_char = 8'h3A;  // ':'
                7'd3:  metrics_char = digit_to_ascii(rms1_mv_d3);
                7'd4:  metrics_char = digit_to_ascii(rms1_mv_d2);
                7'd5:  metrics_char = digit_to_ascii(rms1_mv_d1);
                7'd6:  metrics_char = 8'h20;  // space
                7'd7:  metrics_char = 8'h6D;  // 'm'
                7'd8:  metrics_char = 8'h41;  // 'A'
                7'd9:  metrics_char = 8'h3A;  // ':'
                7'd10: metrics_char = digit_to_ascii(avg1_mv_d3);
                7'd11: metrics_char = digit_to_ascii(avg1_mv_d2);
                7'd12: metrics_char = digit_to_ascii(avg1_mv_d1);
                7'd13: metrics_char = 8'h20;  // space
                7'd14: metrics_char = 8'h20;  // space
                7'd15: metrics_char = 8'h4D;  // 'M'
                7'd16: metrics_char = 8'h3A;  // ':'
                7'd17: metrics_char = digit_to_ascii(max1_mv_d3);
                7'd18: metrics_char = digit_to_ascii(max1_mv_d2);
                7'd19: metrics_char = digit_to_ascii(max1_mv_d1);
                7'd20: metrics_char = 8'h20;  // space
                7'd21: metrics_char = 8'h6D;  // 'm'
                7'd22: metrics_char = 8'h56;  // 'V'
                default: metrics_char = 8'h20;
            endcase
        end

        //=================================================================
        // Row 2: CH2 F:#####Hz  V:####mV  T:X
        //=================================================================
        3'd2: begin
            case (char_cell_x)
                7'd0:  metrics_char = 8'h43;  // 'C'
                7'd1:  metrics_char = 8'h48;  // 'H'
                7'd2:  metrics_char = 8'h32;  // '2'
                7'd3:  metrics_char = 8'h3A;  // ':'
                7'd4:  metrics_char = 8'h46;  // 'F'
                7'd5:  metrics_char = digit_to_ascii(freq2_d5);
                7'd6:  metrics_char = digit_to_ascii(freq2_d4);
                7'd7:  metrics_char = digit_to_ascii(freq2_d3);
                7'd8:  metrics_char = digit_to_ascii(freq2_d2);
                7'd9:  metrics_char = digit_to_ascii(freq2_d1);
                7'd10: metrics_char = 8'h48;  // 'H'
                7'd11: metrics_char = 8'h7A;  // 'z'
                7'd12: metrics_char = 8'h20;  // space
                7'd13: metrics_char = 8'h56;  // 'V'
                7'd14: metrics_char = digit_to_ascii(vpp2_mv_d4);
                7'd15: metrics_char = digit_to_ascii(vpp2_mv_d3);
                7'd16: metrics_char = digit_to_ascii(vpp2_mv_d2);
                7'd17: metrics_char = digit_to_ascii(vpp2_mv_d1);
                7'd18: metrics_char = 8'h6D;  // 'm'
                7'd19: metrics_char = 8'h56;  // 'V'
                7'd20: metrics_char = 8'h20;  // space
                7'd21: metrics_char = 8'h54;  // 'T'
                7'd22: metrics_char = 8'h3A;  // ':'
                7'd23: metrics_char = type_char(type_ch2);
                default: metrics_char = 8'h20;
            endcase
        end

        //=================================================================
        // Row 3: CH2  R:###  A:###  M:###  mV
        //=================================================================
        3'd3: begin
            case (char_cell_x)
                7'd0:  metrics_char = 8'h20;  // space (indent)
                7'd1:  metrics_char = 8'h52;  // 'R'
                7'd2:  metrics_char = 8'h3A;  // ':'
                7'd3:  metrics_char = digit_to_ascii(rms2_mv_d3);
                7'd4:  metrics_char = digit_to_ascii(rms2_mv_d2);
                7'd5:  metrics_char = digit_to_ascii(rms2_mv_d1);
                7'd6:  metrics_char = 8'h20;  // space
                7'd7:  metrics_char = 8'h6D;  // 'm'
                7'd8:  metrics_char = 8'h41;  // 'A'
                7'd9:  metrics_char = 8'h3A;  // ':'
                7'd10: metrics_char = digit_to_ascii(avg2_mv_d3);
                7'd11: metrics_char = digit_to_ascii(avg2_mv_d2);
                7'd12: metrics_char = digit_to_ascii(avg2_mv_d1);
                7'd13: metrics_char = 8'h20;  // space
                7'd14: metrics_char = 8'h20;  // space
                7'd15: metrics_char = 8'h4D;  // 'M'
                7'd16: metrics_char = 8'h3A;  // ':'
                7'd17: metrics_char = digit_to_ascii(max2_mv_d3);
                7'd18: metrics_char = digit_to_ascii(max2_mv_d2);
                7'd19: metrics_char = digit_to_ascii(max2_mv_d1);
                7'd20: metrics_char = 8'h20;  // space
                7'd21: metrics_char = 8'h6D;  // 'm'
                7'd22: metrics_char = 8'h56;  // 'V'
                default: metrics_char = 8'h20;
            endcase
        end

        //=================================================================
        // Row 4: ADC Sample Rate  "ADC:#####kS/s"
        //=================================================================
        3'd4: begin
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
                default: metrics_char = 8'h20;
            endcase
        end

        //=================================================================
        // Row 5: Trigger status  "TRG:###mV STA:XXXXX"
        //=================================================================
        3'd5: begin
            case (char_cell_x)
                7'd0:  metrics_char = 8'h54;  // 'T'
                7'd1:  metrics_char = 8'h52;  // 'R'
                7'd2:  metrics_char = 8'h47;  // 'G'
                7'd3:  metrics_char = 8'h3A;  // ':'
                7'd4:  metrics_char = digit_to_ascii(trig_mv_d3);
                7'd5:  metrics_char = digit_to_ascii(trig_mv_d2);
                7'd6:  metrics_char = digit_to_ascii(trig_mv_d1);
                7'd7:  metrics_char = 8'h6D;  // 'm'
                7'd8:  metrics_char = 8'h56;  // 'V'
                7'd9:  metrics_char = 8'h20;  // space
                7'd10: metrics_char = 8'h53;  // 'S'
                7'd11: metrics_char = 8'h54;  // 'T'
                7'd12: metrics_char = 8'h41;  // 'A'
                7'd13: metrics_char = 8'h3A;  // ':'
                7'd14: metrics_char = trigger_armed ? 8'h41 : 8'h57;  // 'A'=Armed, 'W'=Wait
                7'd15: metrics_char = trigger_armed ? 8'h52 : 8'h41;  // 'R'=aRmed, 'A'=wAit
                7'd16: metrics_char = trigger_armed ? 8'h4D : 8'h49;  // 'M'=arMed, 'I'=waIt
                7'd17: metrics_char = trigger_armed ? 8'h45 : 8'h54;  // 'E'=armEd, 'T'=waiT
                7'd18: metrics_char = 8'h44;  // 'D'
                default: metrics_char = 8'h20;
            endcase
        end

        default: metrics_char = 8'h20;
    endcase
end

//=============================================================================
// Char gen instance for metrics text
//=============================================================================
wire char_pixel_on;

char_gen u_char_gen (
    .clk(clk),
    .char_code(metrics_char),
    .char_row(char_row),       // FIXED: use char_row (3-bit) not char_row_offset (10-bit)
    .char_col(char_col),
    .pixel_on(char_pixel_on)
);

//=============================================================================
// Main Display Output
//=============================================================================
always @(*) begin
    vga_r = 4'h0;
    vga_g = 4'h0;
    vga_b = 4'h0;

    if (de) begin
        //----  Metrics Bar (bottom 48 rows)  ----
        if (in_metrics_bar) begin
            // Dark background
            vga_r = 4'h1; vga_g = 4'h1; vga_b = 4'h1;

            // Separator line at top of metrics bar
            if (pixel_y == 432) begin
                vga_r = 4'h8; vga_g = 4'h8; vga_b = 4'h8;
            end

            // CH1 row backgrounds (yellowish tint: rows 0-1)
            if (char_cell_y == 3'd0) begin
                vga_r = 4'h2; vga_g = 4'h2; vga_b = 4'h0;
            end
            if (char_cell_y == 3'd1) begin
                vga_r = 4'h1; vga_g = 4'h1; vga_b = 4'h0;  // dimmer
            end
            // CH2 row backgrounds (bluish tint: rows 2-3)
            if (char_cell_y == 3'd2) begin
                vga_r = 4'h0; vga_g = 4'h1; vga_b = 4'h2;
            end
            if (char_cell_y == 3'd3) begin
                vga_r = 4'h0; vga_g = 4'h1; vga_b = 4'h1;  // dimmer
            end
            // ADC sample rate row (greenish tint: row 4)
            if (char_cell_y == 3'd4) begin
                vga_r = 4'h0; vga_g = 4'h2; vga_b = 4'h0;
            end
            // Trigger status row (orange tint: row 5)
            if (char_cell_y == 3'd5) begin
                vga_r = 4'h2; vga_g = 4'h1; vga_b = 4'h0;
            end

            // Separator between CH1 and CH2 groups
            if (pixel_y == 448) begin
                vga_r = 4'h4; vga_g = 4'h4; vga_b = 4'h4;
            end

            // Character pixel
            if (char_pixel_on) begin
                // CH1 text: yellow (rows 0-1)
                if (char_cell_y <= 3'd1) begin
                    vga_r = 4'hF; vga_g = 4'hF; vga_b = 4'h0;
                // ADC row: green (row 4)
                end else if (char_cell_y == 3'd4) begin
                    vga_r = 4'h0; vga_g = 4'hF; vga_b = 4'h0;
                // Trigger row: orange (row 5)
                end else if (char_cell_y == 3'd5) begin
                    vga_r = 4'hF; vga_g = 4'hA; vga_b = 4'h0;
                // CH2 text: cyan (rows 2-3)
                end else begin
                    vga_r = 4'h0; vga_g = 4'hF; vga_b = 4'hF;
                end
            end
        end
        //----  Waveform Area (y=0..431)  ----
        else begin
            // Grid
            if (grid_x || grid_y) begin
                vga_r = 4'h2; vga_g = 4'h2; vga_b = 4'h2;
            end
            // Center line (brighter)
            if (center_line) begin
                vga_r = 4'h4; vga_g = 4'h4; vga_b = 4'h4;
            end
            // CH1 waveform (yellow)
            if (hit_ch1) begin
                vga_r = 4'hF; vga_g = 4'hF; vga_b = 4'h0;
            end
            // CH2 waveform (blue)
            if (hit_ch2) begin
                vga_r = 4'h0; vga_g = 4'h0; vga_b = 4'hF;
            end
            // Overlap (white)
            if (hit_ch1 && hit_ch2) begin
                vga_r = 4'hF; vga_g = 4'hF; vga_b = 4'hF;
            end
        end
    end
end

endmodule
