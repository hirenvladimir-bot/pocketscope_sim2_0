`timescale 1ns / 1ps
//=============================================================================
// Waveform Display Module
// Dual-channel oscilloscope display with grid, traces, and metrics overlay.
// Integrates char_gen for on-screen text (frequency, Vpp, waveform type).
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
    // Metrics
    input  wire [15:0]   freq_ch1,
    input  wire [7:0]    vpp_ch1,
    input  wire [1:0]    type_ch1,
    input  wire [15:0]   freq_ch2,
    input  wire [7:0]    vpp_ch2,
    input  wire [1:0]    type_ch2,
    input  wire          meas_valid,
    // VGA output
    output reg  [3:0]    vga_r,
    output reg  [3:0]    vga_g,
    output reg  [3:0]    vga_b
);

//=============================================================================
// ADC value → Y coordinate (full-screen mapping: 0→479)
//=============================================================================
wire [9:0] wave_y_ch1 = 10'd479 - ((wave_ch1 * 10'd479) >> 8);
wire [9:0] wave_y_ch2 = 10'd479 - ((wave_ch2 * 10'd479) >> 8);

//=============================================================================
// Grid & Center Lines
//=============================================================================
wire grid_x  = ((pixel_x % 80) == 0);
wire grid_y  = ((pixel_y % 60) == 0);
wire center_line = (pixel_y == 240);

//=============================================================================
// Waveform hit detection (3-pixel wide traces)
//=============================================================================
wire hit_ch1 = (pixel_y >= ((wave_y_ch1 > 1) ? wave_y_ch1 - 1 : 0)) &&
               (pixel_y <= ((wave_y_ch1 < 478) ? wave_y_ch1 + 1 : 479));
wire hit_ch2 = (pixel_y >= ((wave_y_ch2 > 1) ? wave_y_ch2 - 1 : 0)) &&
               (pixel_y <= ((wave_y_ch2 < 478) ? wave_y_ch2 + 1 : 479));

//=============================================================================
// Metrics Bar Area (pixels y=432..479, 48 rows)
//=============================================================================
wire in_metrics_bar = (pixel_y >= 432);

//=============================================================================
// Character Generator for metrics text
//=============================================================================
wire [2:0] char_col = pixel_x[2:0];
wire [2:0] char_row = (pixel_y - 10'd432);  // offset into metrics area

// Which character cell column (0-79 for 640px / 8)
wire [6:0] char_cell_x = pixel_x[9:3];
wire [2:0] char_cell_y = (pixel_y - 10'd432) >> 3;  // which char row in metrics

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

// Vpp digits (8-bit, 0-255)
wire [3:0] vpp1_d3 = (vpp_ch1 / 8'd100) % 4'd10;
wire [3:0] vpp1_d2 = (vpp_ch1 / 8'd10)  % 4'd10;
wire [3:0] vpp1_d1 = (vpp_ch1)          % 4'd10;

wire [3:0] vpp2_d3 = (vpp_ch2 / 8'd100) % 4'd10;
wire [3:0] vpp2_d2 = (vpp_ch2 / 8'd10)  % 4'd10;
wire [3:0] vpp2_d1 = (vpp_ch2)          % 4'd10;

//=============================================================================
// Character selection mux: pick the right char for current (x,y) in metrics
//=============================================================================
reg [7:0] metrics_char;

// Layout:
//   Row 0 (y=432-439): "CH1 F:#####Hz V:### T:" + type symbol
//   Row 1 (y=440-447): "CH2 F:#####Hz V:### T:" + type symbol
//
// Character positions (cell_x):
//   0:C  1:H  2:1  3:   4:F  5::  6-10: freq digits  11:H  12:z
//   13:  14:V  15::  16-18: Vpp digits
//   20:T  21::  22: type char

always @(*) begin
    metrics_char = 8'h20;  // default: space

    case (char_cell_y)
        3'd0: begin  // CH1 metrics row
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
                7'd11: metrics_char = 8'h5A;  // 'Z'
                7'd12: metrics_char = 8'h20;  // space
                7'd13: metrics_char = 8'h56;  // 'V'
                7'd14: metrics_char = digit_to_ascii(vpp1_d3);
                7'd15: metrics_char = digit_to_ascii(vpp1_d2);
                7'd16: metrics_char = digit_to_ascii(vpp1_d1);
                7'd17: metrics_char = 8'h20;  // space
                7'd18: metrics_char = 8'h54;  // 'T'
                7'd19: metrics_char = (type_ch1 == 2'b01) ? 8'h53 :   // 'S'quare
                                      (type_ch1 == 2'b10) ? 8'h54 :   // 'T'riangle
                                                             8'h53;   // 'S'ine
                default: metrics_char = 8'h20;
            endcase
        end
        3'd1: begin  // CH2 metrics row
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
                7'd11: metrics_char = 8'h5A;  // 'Z'
                7'd12: metrics_char = 8'h20;  // space
                7'd13: metrics_char = 8'h56;  // 'V'
                7'd14: metrics_char = digit_to_ascii(vpp2_d3);
                7'd15: metrics_char = digit_to_ascii(vpp2_d2);
                7'd16: metrics_char = digit_to_ascii(vpp2_d1);
                7'd17: metrics_char = 8'h20;  // space
                7'd18: metrics_char = 8'h54;  // 'T'
                7'd19: metrics_char = (type_ch2 == 2'b01) ? 8'h53 :
                                      (type_ch2 == 2'b10) ? 8'h54 :
                                                             8'h53;
                default: metrics_char = 8'h20;
            endcase
        end
        default: metrics_char = 8'h20;  // space
    endcase
end

//=============================================================================
// Char gen instance for metrics text
//=============================================================================
wire char_pixel_on;

char_gen u_char_gen (
    .clk(clk),
    .char_code(metrics_char),
    .char_row(char_row),
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

            // CH1 text row background tint (yellowish)
            if (char_cell_y == 3'd0) begin
                vga_r = 4'h2; vga_g = 4'h2; vga_b = 4'h0;
            end
            // CH2 text row background tint (bluish)
            if (char_cell_y == 3'd1) begin
                vga_r = 4'h0; vga_g = 4'h1; vga_b = 4'h2;
            end

            // Character pixel
            if (char_pixel_on) begin
                // CH1 text: yellow, CH2 text: cyan
                if (char_cell_y == 3'd0) begin
                    vga_r = 4'hF; vga_g = 4'hF; vga_b = 4'h0;
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
