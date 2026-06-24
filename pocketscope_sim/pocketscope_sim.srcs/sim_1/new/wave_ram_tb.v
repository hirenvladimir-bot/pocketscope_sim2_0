`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 2026/06/04 17:50:56
// Design Name: 
// Module Name: wave_ram_tb
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




module wave_ram_tb;

reg clk;
reg we;

reg [9:0] wr_addr;
reg [9:0] rd_addr;

reg [7:0] din;
wire [7:0] dout;

wave_ram_ch1 uut(
    .clk(clk),
    .we(we),
    .wr_addr(wr_addr),
    .din(din),
    .rd_addr(rd_addr),
    .dout(dout)
);

initial begin
    clk = 0;
    forever #20 clk = ~clk;
end

integer i;

initial begin

    we = 0;
    wr_addr = 0;
    rd_addr = 0;
    din = 0;

    #100;

    // 写入测试数据
    we = 1;

    for(i=0;i<16;i=i+1)
    begin
        @(posedge clk);
        wr_addr <= i;
        din <= i + 8'h10;
    end

    @(posedge clk);
    we <= 0;

    // 读取验证
    for(i=0;i<16;i=i+1)
    begin
        @(posedge clk);
        rd_addr <= i;
    end

    #1000;
    $finish;

end

endmodule