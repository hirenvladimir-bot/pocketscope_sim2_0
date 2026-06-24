`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 2026/06/04 16:30:54
// Design Name: 
// Module Name: wave_ram_ch1
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


module wave_ram_ch1
(
    input wire clk,

    // 写端口
    input wire we,
    input wire [9:0] wr_addr,
    input wire [7:0] din,

    // 读端口
    input wire [9:0] rd_addr,
    output reg [7:0] dout
);

reg [7:0] ram [0:1023];

always @(posedge clk)
begin
    if(we)
        ram[wr_addr] <= din;
end

always @(posedge clk)
begin
    dout <= ram[rd_addr];
end

endmodule
