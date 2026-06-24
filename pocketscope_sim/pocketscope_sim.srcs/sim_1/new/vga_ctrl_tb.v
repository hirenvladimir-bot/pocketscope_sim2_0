`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 2026/06/04 17:51:52
// Design Name: 
// Module Name: vga_ctrl_tb
// Project Name: 
// Target Devices: 
// Tool Versions: 
// Description: 
// 
// Dependencies: 
// 
// Revision:
// Revision 0.01 - File Created
// Additional Comments:
// 
//////////////////////////////////////////////////////////////////////////////////




module vga_ctrl_tb;

reg clk;
reg rst_n;

wire hsync;
wire vsync;
wire de;

wire [9:0] pixel_x;
wire [9:0] pixel_y;

vga_ctrl uut(
    .clk(clk),
    .rst_n(rst_n),

    .hsync(hsync),
    .vsync(vsync),
    .de(de),

    .pixel_x(pixel_x),
    .pixel_y(pixel_y)
);

initial begin
    clk = 0;
    forever #20 clk = ~clk;
end

initial begin
    rst_n = 0;
    #200;
    rst_n = 1;
end

initial begin
    #5_000_000;
    $finish;
end

endmodule