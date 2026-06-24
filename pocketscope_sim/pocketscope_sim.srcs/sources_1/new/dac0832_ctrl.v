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

    assign dac_ile   = 1'b1;
    assign dac_cs_n  = 1'b0;
    assign dac_wr2_n = 1'b0;
    assign dac_xfer_n = 1'b0;

    // WR1# write timing: 16 cycles (160ns) low pulse
    reg [4:0] wr_cnt;
    reg       wr_active;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            dac_d      <= 8'h80;
            dac_wr1_n  <= 1'b1;
            wr_cnt     <= 0;
            wr_active  <= 1'b0;
        end else begin
            if (dac_update && !wr_active) begin
                dac_d      <= dac_data_in;
                wr_active  <= 1'b1;
                wr_cnt     <= 0;
                dac_wr1_n  <= 1'b0;
            end else if (wr_active) begin
                if (wr_cnt == 15) begin
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
