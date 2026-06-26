`timescale 1ns / 1ps
// DAC0832 8-bit parallel interface controller
// Single-buffered mode: ILE=1, CS#=0, WR1# latches data
// WR2#=0, XFER#=0 for transparent second stage

module dac0832_ctrl
(
    input  wire          clk,
    input  wire          rst_n,
    input  wire [7:0]    dac_data_in,
    input  wire          dac_update,
    output reg  [7:0]    dac_d,
    output wire          dac_ile,
    output wire          dac_cs_n,
    output reg           dac_wr1_n,
    output wire          dac_wr2_n,
    output wire          dac_xfer_n
);

    // DAC_ZERO: digital code that produces 0V at the analog output
    // 0x80 (128) for bipolar DAC configuration
    parameter DAC_ZERO = 8'h80;

    assign dac_ile   = 1'b1;
    assign dac_cs_n  = 1'b0;
    assign dac_wr2_n = 1'b0;
    assign dac_xfer_n = 1'b0;

    // WR1# write timing: 16-cycle low pulse, 4-cycle data setup before WR#
    // This provides 4 clk_25m cycles (160ns) of data setup time before WR# falls,
    // exceeding DAC0832 minimum setup time requirement of 100ns.
    // Total write cycle: 21 cycles (840ns), update period: 24 cycles (960ns),
    // leaving 3-cycle (120ns) idle gap between writes.
    reg [4:0] wr_cnt;
    reg       wr_active;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            dac_d      <= DAC_ZERO;
            dac_wr1_n  <= 1'b1;
            wr_cnt     <= 0;
            wr_active  <= 1'b0;
        end else begin
            if (dac_update && !wr_active) begin
                // Phase 0: load new data, keep WR# high (setup time)
                dac_d      <= dac_data_in;
                wr_active  <= 1'b1;
                wr_cnt     <= 1;
                // dac_wr1_n stays 1 (retained from previous state)
            end else if (wr_active) begin
                if (wr_cnt == 4) begin
                    // Phase 4: assert WR# four cycles after data change (160ns setup)
                    dac_wr1_n  <= 1'b0;
                    wr_cnt     <= wr_cnt + 1'b1;
                end else if (wr_cnt == 20) begin
                    // Phase 20: de-assert WR# after 16-cycle low pulse (640ns)
                    dac_wr1_n  <= 1'b1;
                    wr_active  <= 1'b0;
                end else begin
                    wr_cnt <= wr_cnt + 1'b1;
                end
            end else begin
                dac_wr1_n <= 1'b1;
            end
        end
    end

endmodule
