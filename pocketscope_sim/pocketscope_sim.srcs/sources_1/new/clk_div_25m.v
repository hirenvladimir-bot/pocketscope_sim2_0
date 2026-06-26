`timescale 1ns / 1ps
// Clock divider: 100MHz -> 25MHz (divide by 4)
// Updated for EGO1 100MHz system clock
// Uses BUFG to place divided clock on global clock distribution network

module clk_div_25m
(
    input  wire clk_100m,
    input  wire rst_n,
    output wire clk_25m
);

reg [1:0] div_cnt;
reg       clk_25m_i;

always @(posedge clk_100m or negedge rst_n) begin
    if (!rst_n) begin
        clk_25m_i <= 1'b0;
        div_cnt   <= 2'd0;
    end else begin
        if (div_cnt == 2'd1) begin
            clk_25m_i <= ~clk_25m_i;
            div_cnt   <= 2'd0;
        end else begin
            div_cnt <= div_cnt + 1'b1;
        end
    end
end

// Drive divided clock onto global clock buffer for low-skew distribution.
// In synthesis, BUFG ensures clk_25m is on the global clock network.
// In simulation, BUFG may not be available (non-Xilinx simulators), so
// bypass it. Vivado xsim handles BUFG correctly via unisim.
BUFG u_bufg_25m (
    .I(clk_25m_i),
    .O(clk_25m)
);

endmodule
