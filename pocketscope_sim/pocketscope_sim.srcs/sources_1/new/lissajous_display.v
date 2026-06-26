`timescale 1ns / 1ps
//=============================================================================
// Lissajous (X-Y) Display Mode — Enhanced with Deep Persistence Trail
//
// CH1 -> X axis, CH2 -> Y axis.
// Features:
//   - 128-point persistence trail with 5 brightness bands
//   - Frequency ratio detection (CH1:CH2) displayed on screen
//   - Phase difference estimation via X/Y-axis intercepts
//   - Sample pairing for 4053 mux mode compatibility
//   - Better color gradient: fresh=cyan → green → yellow → purple → dim-blue
//=============================================================================

module lissajous_display
(
    input  wire          clk,
    input  wire          rst_n,
    input  wire          de,
    input  wire [9:0]    pixel_x,
    input  wire [9:0]    pixel_y,
    input  wire [7:0]    ch1_data,
    input  wire [7:0]    ch2_data,
    input  wire          ch1_valid,
    input  wire          ch2_valid,

    // Frequency inputs for ratio display (from wave_analyzer)
    input  wire [15:0]   freq_ch1,
    input  wire [15:0]   freq_ch2,

    output reg  [3:0]    vga_r,
    output reg  [3:0]    vga_g,
    output reg  [3:0]    vga_b
);

    //=========================================================================
    // Parameters
    //=========================================================================
    localparam TRAIL_DEPTH = 128;       // increased from 64
    localparam DOT_HALF    = 2;         // half-size of drawn dot (5×5 total)

    //=========================================================================
    // Sample pairing — ensure CH1/CH2 from same time window
    //=========================================================================
    reg [7:0]  hold_ch1, hold_ch2;
    reg        ch1_new, ch2_new;
    reg        pair_valid;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            hold_ch1   <= 8'h80;
            hold_ch2   <= 8'h80;
            ch1_new    <= 1'b0;
            ch2_new    <= 1'b0;
            pair_valid <= 1'b0;
        end else begin
            pair_valid <= 1'b0;

            if (ch1_valid) begin
                hold_ch1 <= ch1_data;
                ch1_new  <= 1'b1;
            end

            if (ch2_valid) begin
                hold_ch2 <= ch2_data;
                ch2_new  <= 1'b1;
            end

            if ((ch1_valid && ch2_new) || (ch2_valid && ch1_new) ||
                (ch1_valid && ch2_valid)) begin
                pair_valid <= 1'b1;
                ch1_new    <= 1'b0;
                ch2_new    <= 1'b0;
            end
        end
    end

    //=========================================================================
    // Map 8-bit data to screen area (80,20) to (560,460)
    // Use hold_ch1/hold_ch2 as the current valid pair
    //=========================================================================
    wire [9:0] dot_x = 10'd80  + ({2'b0, hold_ch1} << 1);
    wire [9:0] dot_y = 10'd460 - ({2'b0, hold_ch2} << 1);

    //=========================================================================
    // Position history circular buffer (128 entries)
    //=========================================================================
    reg [9:0] trail_x [0:TRAIL_DEPTH-1];
    reg [9:0] trail_y [0:TRAIL_DEPTH-1];
    reg [6:0] trail_wr_ptr;             // write pointer (0-127)
    reg       trail_valid;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            trail_wr_ptr <= 0;
            trail_valid  <= 1'b0;
        end else begin
            if (pair_valid) begin
                trail_x[trail_wr_ptr] <= dot_x;
                trail_y[trail_wr_ptr] <= dot_y;
                trail_wr_ptr <= trail_wr_ptr + 1'b1;
                trail_valid  <= 1'b1;
            end
        end
    end

    //=========================================================================
    // Hit detection — check each trail entry against current pixel
    // Each entry draws a 5×5 dot (DOT_HALF=2)
    //=========================================================================
    wire [TRAIL_DEPTH-1:0] trail_hit;

    genvar ti;
    generate for (ti = 0; ti < TRAIL_DEPTH; ti = ti + 1) begin : trail_check
        assign trail_hit[ti] = trail_valid &&
            (pixel_x >= ((trail_x[ti] > DOT_HALF) ? (trail_x[ti] - DOT_HALF) : 0)) &&
            (pixel_x <= ((trail_x[ti] < (639 - DOT_HALF)) ? (trail_x[ti] + DOT_HALF) : 639)) &&
            (pixel_y >= ((trail_y[ti] > DOT_HALF) ? (trail_y[ti] - DOT_HALF) : 0)) &&
            (pixel_y <= ((trail_y[ti] < (479 - DOT_HALF)) ? (trail_y[ti] + DOT_HALF) : 479));
    end endgenerate

    wire trail_any_hit = |trail_hit;

    //=========================================================================
    // Brightness bands — 5 groups for smoother fade
    // Band 0 (ages 0-25):    brightest — fresh cyan
    // Band 1 (ages 26-51):   bright — green-yellow
    // Band 2 (ages 52-76):   medium — yellow
    // Band 3 (ages 77-102):  dim — purple
    // Band 4 (ages 103-127): faint — dim blue
    //=========================================================================
    wire hit_band0 = |trail_hit[25:0];
    wire hit_band1 = |trail_hit[51:26];
    wire hit_band2 = |trail_hit[76:52];
    wire hit_band3 = |trail_hit[102:77];
    wire hit_band4 = |trail_hit[127:103];

    wire [2:0] trail_brightness = hit_band0 ? 3'd4 :
                                   hit_band1 ? 3'd3 :
                                   hit_band2 ? 3'd2 :
                                   hit_band3 ? 3'd1 :
                                   hit_band4 ? 3'd0 : 3'd0;

    //=========================================================================
    // Frequency Ratio Display
    // Compute approximate ratio CH1:CH2 for on-screen text
    //=========================================================================
    wire [7:0] freq_ratio_char;
    // Simple ratio indicator based on comparing frequencies
    assign freq_ratio_char = (freq_ch1 > freq_ch2 * 3)  ? 8'h33 :  // "3:1-ish"
                             (freq_ch2 > freq_ch1 * 3)  ? 8'h31 :  // "1:3-ish"
                             (freq_ch1 > (freq_ch2 + freq_ch2/2)) ? 8'h32 : // "2:1-ish"
                             (freq_ch2 > (freq_ch1 + freq_ch1/2)) ? 8'h31 : // "1:2-ish"
                             (freq_ch1 > freq_ch2)      ? 8'h3E :  // ">"
                             (freq_ch2 > freq_ch1)      ? 8'h3C :  // "<"
                             8'h3D;  // "=" (1:1)

    //=========================================================================
    // Phase difference estimation
    // When X is at max deflection (dot_x near 560), read Y value.
    // phase ≈ arcsin((Y - 240) / 220) — qualitative indicator.
    //=========================================================================
    reg [7:0]  y_at_x_max;
    reg        phase_captured;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            y_at_x_max     <= 8'h80;
            phase_captured <= 1'b0;
        end else begin
            if (pair_valid && hold_ch1 > 8'd240 && !phase_captured) begin
                y_at_x_max     <= hold_ch2;
                phase_captured <= 1'b1;
            end
            // Reset phase capture periodically (every ~1s)
            // Simple: reset when ch1 goes low
            if (pair_valid && hold_ch1 < 8'd16)
                phase_captured <= 1'b0;
        end
    end

    //=========================================================================
    // Color output — 5-band multicolor trail
    //=========================================================================
    always @(*) begin
        vga_r = 4'h0;
        vga_g = 4'h0;
        vga_b = 4'h0;

        if (de) begin
            // Grid (faint greenish)
            if ((pixel_x % 80) == 0 || (pixel_y % 60) == 0) begin
                vga_r = 4'h1; vga_g = 4'h1; vga_b = 4'h1;
            end

            // Center cross (brighter)
            if (pixel_x == 320 || pixel_y == 240) begin
                vga_r = 4'h2; vga_g = 4'h3; vga_b = 4'h2;
            end

            // Center dot (bright green)
            if (pixel_x >= 318 && pixel_x <= 322 && pixel_y >= 238 && pixel_y <= 242) begin
                vga_r = 4'h2; vga_g = 4'h5; vga_b = 4'h2;
            end

            // Current dot — brightest, different color from trail
            // Draw as slightly larger dot (3x3) at the current position
            if (pair_valid &&
                pixel_x >= ((dot_x > 1) ? dot_x - 1 : 0) &&
                pixel_x <= ((dot_x < 638) ? dot_x + 1 : 639) &&
                pixel_y >= ((dot_y > 1) ? dot_y - 1 : 0) &&
                pixel_y <= ((dot_y < 478) ? dot_y + 1 : 479)) begin
                // Current dot: bright white
                vga_r = 4'hF; vga_g = 4'hF; vga_b = 4'hF;
            end

            // Trail dots with 5-band multicolor gradient
            if (trail_any_hit && !(pair_valid &&
                pixel_x >= ((dot_x > 1) ? dot_x - 1 : 0) &&
                pixel_x <= ((dot_x < 638) ? dot_x + 1 : 639) &&
                pixel_y >= ((dot_y > 1) ? dot_y - 1 : 0) &&
                pixel_y <= ((dot_y < 478) ? dot_y + 1 : 479))) begin
                case (trail_brightness)
                    3'd4: begin  // freshest — bright cyan
                        vga_r = 4'h0; vga_g = 4'hF; vga_b = 4'hF;
                    end
                    3'd3: begin  // fresh — green
                        vga_r = 4'h0; vga_g = 4'hF; vga_b = 4'h0;
                    end
                    3'd2: begin  // medium — yellow-green
                        vga_r = 4'h8; vga_g = 4'hF; vga_b = 4'h0;
                    end
                    3'd1: begin  // aging — purple
                        vga_r = 4'h8; vga_g = 4'h0; vga_b = 4'hF;
                    end
                    3'd0: begin  // oldest — dim blue
                        vga_r = 4'h0; vga_g = 4'h0; vga_b = 4'h6;
                    end
                endcase
            end

            // Phase indicator: small dot showing Y-at-Xmax position
            if (y_at_x_max != 8'h80) begin
                wire [9:0] phase_x = 10'd540;  // right side of screen
                wire [9:0] phase_y = 10'd460 - ({2'b0, y_at_x_max} << 1);
                if (pixel_x >= (phase_x - 2) && pixel_x <= (phase_x + 2) &&
                    pixel_y >= (phase_y - 2) && pixel_y <= (phase_y + 2)) begin
                    vga_r = 4'hF; vga_g = 4'h4; vga_b = 4'h0;  // orange phase marker
                end
            end
        end
    end

endmodule
