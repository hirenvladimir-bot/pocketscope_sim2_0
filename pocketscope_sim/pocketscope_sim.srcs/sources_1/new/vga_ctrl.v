`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 2026/06/04 16:39:42
// Design Name: 
// Module Name: vga_ctrl
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


module vga_ctrl
(
    input wire clk,
    input wire rst_n,

    output reg hsync,
    output reg vsync,

    output wire de,

    output reg [9:0] pixel_x,
    output reg [9:0] pixel_y
);

//==================================================
// 640x480@60Hz
// Pixel Clock = 25MHz
//==================================================

localparam H_VISIBLE = 640;
localparam H_FRONT   = 16;
localparam H_SYNC    = 96;
localparam H_BACK    = 48;
localparam H_TOTAL   = 800;

localparam V_VISIBLE = 480;
localparam V_FRONT   = 10;
localparam V_SYNC    = 2;
localparam V_BACK    = 33;
localparam V_TOTAL   = 525;

//==================================================
// 行列计数器
//==================================================

reg [9:0] h_cnt;
reg [9:0] v_cnt;

always @(posedge clk or negedge rst_n)
begin

    if(!rst_n)
    begin
        h_cnt <= 0;
        v_cnt <= 0;
    end
    else
    begin

        if(h_cnt == H_TOTAL-1)
        begin

            h_cnt <= 0;

            if(v_cnt == V_TOTAL-1)
                v_cnt <= 0;
            else
                v_cnt <= v_cnt + 1'b1;

        end
        else
        begin

            h_cnt <= h_cnt + 1'b1;

        end

    end

end

//==================================================
// HSYNC
//==================================================

always @(posedge clk)
begin

    if(
        h_cnt >= (H_VISIBLE + H_FRONT)
        &&
        h_cnt <  (H_VISIBLE + H_FRONT + H_SYNC)
    )
        hsync <= 1'b0;
    else
        hsync <= 1'b1;

end

//==================================================
// VSYNC
//==================================================

always @(posedge clk)
begin

    if(
        v_cnt >= (V_VISIBLE + V_FRONT)
        &&
        v_cnt <  (V_VISIBLE + V_FRONT + V_SYNC)
    )
        vsync <= 1'b0;
    else
        vsync <= 1'b1;

end

//==================================================
// DE
//==================================================

assign de =
(
    (h_cnt < H_VISIBLE)
    &&
    (v_cnt < V_VISIBLE)
);

//==================================================
// 像素坐标
//==================================================

always @(posedge clk)
begin

    if(de)
    begin
        pixel_x <= h_cnt;
        pixel_y <= v_cnt;
    end
    else
    begin
        pixel_x <= 0;
        pixel_y <= 0;
    end

end

endmodule