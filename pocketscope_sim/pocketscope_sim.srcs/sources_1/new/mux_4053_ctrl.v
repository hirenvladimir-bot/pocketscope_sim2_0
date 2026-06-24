`timescale 1ns / 1ps
//=============================================================================
// 74HC4053 Analog Switch Controller (Reference Module)
//
// NOTE: This is a standalone reference implementation. The production code
// in xadc_reader.v (USE_4053=1) integrates this logic directly into the
// XADC DRP state machine for tighter timing control.
//
// Use this module if you need a standalone 4053 controller for a different
// ADC configuration or for simulation/test purposes.
//=============================================================================

module mux_4053_ctrl
#(
    parameter SETTLE_CYCLES = 10     // 100ns settle at 100MHz (100ns > 60ns max)
)
(
    input  wire       clk,           // 100MHz system clock (same as XADC DCLK)
    input  wire       rst_n,
    input  wire       adc_drdy,      // XADC data ready strobe (1 cycle pulse)
    output reg        mux_sel,       // 4053 channel select (0=CH1, 1=CH2)
    output reg        channel_sel,   // which channel the JUST-READ data belongs to (0=CH1, 1=CH2)
    output reg        ready_for_next // high when mux settled and ready for next DEN
);

    reg [7:0] settle_cnt;
    reg       settling;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            mux_sel        <= 1'b0;
            channel_sel    <= 1'b0;
            settle_cnt     <= 0;
            settling       <= 1'b0;
            ready_for_next <= 1'b1;   // ready after reset
        end else begin
            // Default: ready after settle period completes
            if (settling) begin
                if (settle_cnt == SETTLE_CYCLES - 1) begin
                    settling       <= 1'b0;
                    settle_cnt     <= 0;
                    ready_for_next <= 1'b1;
                end else begin
                    settle_cnt <= settle_cnt + 1'b1;
                end
            end

            // On DRDY: latch which channel this data belongs to, then toggle mux
            if (adc_drdy) begin
                channel_sel    <= mux_sel;          // record which channel was sampled
                mux_sel        <= ~mux_sel;         // switch to other channel
                settling       <= 1'b1;              // begin settle period
                ready_for_next <= 1'b0;              // not ready until settled
                settle_cnt     <= 0;
            end
        end
    end

endmodule
