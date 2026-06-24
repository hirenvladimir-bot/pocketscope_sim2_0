`timescale 1ns / 1ps
// Lissajous (X-Y) Display Mode
// CH1 -> X axis, CH2 -> Y axis
// Shows current dot with grid

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

    // Map 8-bit data to screen area (80,20) to (560,460)
    wire [9:0] dot_x = 10'd80  + ({2'b0, ch1_data} << 1);
    wire [9:0] dot_y = 10'd460 - ({2'b0, ch2_data} << 1);

    // Simple persistence: hold last dot position
    reg [9:0] hold_x, hold_y;
    reg       dot_valid;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            hold_x    <= 320;
            hold_y    <= 240;
            dot_valid <= 1'b0;
        end else begin
            if (ch1_valid || ch2_valid) begin
                hold_x    <= dot_x;
                hold_y    <= dot_y;
                dot_valid <= 1'b1;
            end
        end
    end

    always @(*) begin
        vga_r = 4'h0;
        vga_g = 4'h0;
        vga_b = 4'h0;

        if (de) begin
            // Grid
            if ((pixel_x % 80) == 0 || (pixel_y % 60) == 0) begin
                vga_r = 4'h1; vga_g = 4'h1; vga_b = 4'h1;
            end

            // Center cross
            if (pixel_x == 320 || pixel_y == 240) begin
                vga_r = 4'h2; vga_g = 4'h2; vga_b = 4'h2;
            end

            // Current dot (3x3 pixel)
            if (dot_valid &&
                pixel_x >= ((hold_x>0) ? hold_x-1 : 0) &&
                pixel_x <= ((hold_x<639) ? hold_x+1 : 639) &&
                pixel_y >= ((hold_y>0) ? hold_y-1 : 0) &&
                pixel_y <= ((hold_y<479) ? hold_y+1 : 479)) begin
                vga_r = 4'h0; vga_g = 4'hF; vga_b = 4'h0;
            end
        end
    end

endmodule
