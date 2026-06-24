`timescale 1ns / 1ps
// Scroll address generator for oscilloscope waveform display
// Updated with configurable scroll speed

module scroll_addr_gen
#(
    parameter SCROLL_DIV = 50000
)
(
    input  wire          clk,
    input  wire          rst_n,
    input  wire [9:0]    pixel_x,
    output wire [9:0]    display_addr,
    output reg  [9:0]    shift
);

reg [15:0] div_cnt;

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        div_cnt <= 0;
        shift   <= 0;
    end else begin
        if (div_cnt == SCROLL_DIV - 1) begin
            div_cnt <= 0;
            shift   <= shift + 1'b1;
        end else begin
            div_cnt <= div_cnt + 1'b1;
        end
    end
end

assign display_addr = pixel_x + shift;

endmodule
