`timescale 1ns / 1ps
//=============================================================================
// Lissajous (X-Y) Display Mode with Persistence Trail
// CH1 -> X axis, CH2 -> Y axis
// Shows current dot + 64-point history trail with gradient brightness.
//
// FIX: In 4053 mux mode, CH1/CH2 samples arrive alternately. The pair_valid
// mechanism ensures we only capture dots when BOTH channels have fresh data,
// avoiding distorted X-Y patterns from stale/mismatched channel values.
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

    output reg  [3:0]    vga_r,
    output reg  [3:0]    vga_g,
    output reg  [3:0]    vga_b
);

    //=========================================================================
    // Parameters
    //=========================================================================
    localparam TRAIL_DEPTH = 64;        // number of history points
    localparam DOT_HALF    = 2;         // half-size of drawn dot (5x5 total)

    //=========================================================================
    // Sample pairing: ensure CH1 and CH2 data are from the same time window.
    // In 4053 mux mode, ch1_valid and ch2_valid alternate; we need to pair
    // consecutive samples to form a valid (X,Y) coordinate.
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

            // Capture CH1
            if (ch1_valid) begin
                hold_ch1 <= ch1_data;
                ch1_new  <= 1'b1;
            end

            // Capture CH2
            if (ch2_valid) begin
                hold_ch2 <= ch2_data;
                ch2_new  <= 1'b1;
            end

            // When both channels have fresh data, we have a valid pair
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
    // Position history circular buffer (64 entries)
    // Only written when pair_valid indicates both channels have fresh data.
    //=========================================================================
    reg [9:0] trail_x [0:TRAIL_DEPTH-1];
    reg [9:0] trail_y [0:TRAIL_DEPTH-1];
    reg [5:0] trail_wr_ptr;             // write pointer (0-63)
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
    // Each entry draws a (2*DOT_HALF+1) × (2*DOT_HALF+1) = 5×5 dot
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
    // Brightness bands (4 groups of 16 entries)
    // Band 0 (ages 0-15):  brightest — fresh green
    // Band 1 (ages 16-31): medium
    // Band 2 (ages 32-47): dim
    // Band 3 (ages 48-63): faintest
    //=========================================================================
    wire hit_band0 = |trail_hit[15:0];
    wire hit_band1 = |trail_hit[31:16];
    wire hit_band2 = |trail_hit[47:32];
    wire hit_band3 = |trail_hit[63:48];

    // Priority: brighter bands win (band 0 > band 1 > band 2 > band 3)
    wire [1:0] trail_brightness = hit_band0 ? 2'd3 :
                                   hit_band1 ? 2'd2 :
                                   hit_band2 ? 2'd1 :
                                   hit_band3 ? 2'd0 : 2'd0;

    //=========================================================================
    // Color output — multicolor trail for visual appeal
    //=========================================================================
    always @(*) begin
        vga_r = 4'h0;
        vga_g = 4'h0;
        vga_b = 4'h0;

        if (de) begin
            // Grid (faint)
            if ((pixel_x % 80) == 0 || (pixel_y % 60) == 0) begin
                vga_r = 4'h1; vga_g = 4'h1; vga_b = 4'h1;
            end

            // Center cross
            if (pixel_x == 320 || pixel_y == 240) begin
                vga_r = 4'h2; vga_g = 4'h2; vga_b = 4'h2;
            end

            // Trail dots with multicolor gradient
            // Fresh dots: bright cyan → older: magenta → oldest: dim blue
            if (trail_any_hit) begin
                case (trail_brightness)
                    2'd3: begin  // freshest — bright cyan-green
                        vga_r = 4'h0; vga_g = 4'hF; vga_b = 4'hA;
                    end
                    2'd2: begin  // medium — green
                        vga_r = 4'h0; vga_g = 4'hA; vga_b = 4'h0;
                    end
                    2'd1: begin  // dim — purple
                        vga_r = 4'h5; vga_g = 4'h0; vga_b = 4'hA;
                    end
                    2'd0: begin  // faintest — dim blue
                        vga_r = 4'h0; vga_g = 4'h0; vga_b = 4'h5;
                    end
                endcase
            end
        end
    end

endmodule
