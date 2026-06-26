`timescale 1ns / 1ps
// Scroll address generator for oscilloscope waveform display
// Generates a continuous write address; trigger_reset repositions the
// write pointer so the trigger event aligns with screen center (~512 px).

module scroll_addr_gen
#(
    parameter SCROLL_DIV = 50000   // scroll speed divider (50k @25MHz = 2ms/px)
)
(
    input  wire          clk,
    input  wire          rst_n,
    input  wire [9:0]    pixel_x,
    input  wire          trigger_reset,   // pulse: resets write addr to screen center
    output wire [9:0]    display_addr,
    output reg  [9:0]    shift
);

reg [15:0] div_cnt;

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        div_cnt <= 0;
        shift   <= 0;
    end else begin
        // Trigger: reset write position to align trigger event with screen center
        if (trigger_reset) begin
            shift   <= 10'd512;  // place trigger point at center of 1024-sample buffer
            div_cnt <= 0;
        end else if (div_cnt == SCROLL_DIV - 1) begin
            div_cnt <= 0;
            shift   <= shift + 1'b1;
        end else begin
            div_cnt <= div_cnt + 1'b1;
        end
    end
end

assign display_addr = pixel_x + shift;

endmodule
