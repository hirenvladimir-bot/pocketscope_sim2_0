`timescale 1ns / 1ps
// XADC Dual-Channel Reader via DRP
//
// Two operating modes, selected by USE_4053 parameter:
//
//   USE_4053=0 (default) — Original dual-XADC-channel mode
//     CH1: AD2 (VAUXP[2]/VAUXN[2]) on DRP addr 0x12
//     CH2: AD3 (VAUXP[3]/VAUXN[3]) on DRP addr 0x13
//     Alternates DRP addresses each conversion cycle.
//
//   USE_4053=1 — Single-XADC-channel + 74HC4053 external mux mode
//     Both physical inputs go through a 4053 analog switch into ONE XADC
//     auxiliary channel (default VAUXP[2]/VAUXN[2], DRP addr 0x12).
//     mux_sel output toggles each conversion to switch the 4053 between
//     CH1 and CH2. A settle delay ensures the 4053 output is stable
//     before the next XADC conversion begins.
//
// SIM_MODE=1 bypasses XADC for pure-digital simulation.

module xadc_reader
#(
    parameter SIM_MODE       = 1,
    parameter USE_4053       = 0,        // 0=dual XADC channel, 1=single ch + 4053 mux
    parameter SINGLE_CH_ADDR = 7'h12,    // XADC DRP addr when USE_4053=1 (VAUXP[2])
    parameter SETTLE_CYCLES  = 10        // 4053 settle time in DCLK cycles (100ns @100MHz)
)
(
    input  wire          clk,
    input  wire          rst_n,
    input  wire [15:0]   vauxp,
    input  wire [15:0]   vauxn,
    input  wire          vp_in,
    input  wire          vn_in,
    output wire [11:0]   ch1_data,
    output wire          ch1_valid,
    output wire [11:0]   ch2_data,
    output wire          ch2_valid,
    // 4053 control (only used when USE_4053=1)
    output wire          mux_sel         // 0=CH1 routed to ADC, 1=CH2 routed to ADC
);

    generate
    if (SIM_MODE) begin : sim_mode

        // ----------------------------------------------------------------
        // Simulation mode: generate test ramp data
        // ----------------------------------------------------------------
        reg [11:0] sim_ch1, sim_ch2;
        reg        sim_vld1, sim_vld2;
        reg [9:0]  sim_cnt;
        reg        sim_mux_sel;

        assign ch1_data  = sim_ch1;
        assign ch1_valid = sim_vld1;
        assign ch2_data  = sim_ch2;
        assign ch2_valid = sim_vld2;
        assign mux_sel   = USE_4053 ? sim_mux_sel : 1'b0;

        always @(posedge clk or negedge rst_n) begin
            if (!rst_n) begin
                sim_cnt     <= 0;
                sim_ch1     <= 12'h800;
                sim_ch2     <= 12'h400;
                sim_vld1    <= 0;
                sim_vld2    <= 0;
                sim_mux_sel <= 1'b0;
            end else begin
                sim_vld1 <= 0;
                sim_vld2 <= 0;
                if (sim_cnt == 999) begin
                    sim_cnt <= 0;
                    if (USE_4053) begin
                        // 4053 mode: alternate channels each sample
                        if (sim_mux_sel) begin
                            sim_ch2     <= sim_ch2 + 12'd3;
                            sim_vld2    <= 1;
                        end else begin
                            sim_ch1     <= sim_ch1 + 12'd1;
                            sim_vld1    <= 1;
                        end
                        sim_mux_sel <= ~sim_mux_sel;
                    end else begin
                        // Original dual-channel mode
                        sim_ch1  <= sim_ch1 + 12'd1;
                        sim_ch2  <= sim_ch2 + 12'd3;
                        sim_vld1 <= 1;
                        sim_vld2 <= 1;
                    end
                end else begin
                    sim_cnt <= sim_cnt + 1'b1;
                end
            end
        end

    end else begin : hw_mode

        // ----------------------------------------------------------------
        // Hardware mode: XADC via DRP
        // ----------------------------------------------------------------
        wire [15:0] drp_do;
        wire        drp_drdy;
        wire [6:0]  drp_daddr;
        wire        drp_den;

        XADC #(
            .INIT_40(16'h1000),
            .INIT_41(16'h2000),
            .INIT_42(16'h0800),
            .SIM_MONITOR_FILE("xadc_stimulus.txt")
        ) u_xadc (
            .DCLK       (clk),
            .RESET      (~rst_n),
            .VAUXP      (vauxp),
            .VAUXN      (vauxn),
            .VP         (vp_in),
            .VN         (vn_in),
            .CONVST     (1'b0),         // continuous sampling mode (no external trigger)
            .CONVSTCLK  (1'b0),         // unused in continuous mode
            .DI         (16'h0000),
            .DADDR      (drp_daddr),
            .DEN        (drp_den),
            .DWE        (1'b0),
            .DO         (drp_do),
            .DRDY       (drp_drdy),
            .EOC        (),
            .CHANNEL    (),
            .BUSY       (),
            .EOS        (),
            .JTAGBUSY   (),
            .JTAGLOCKED (),
            .JTAGMODIFIED(),
            .OT         (),
            .ALM        (),
            .MUXADDR    ()
        );

        // ----------------------------------------------------------------
        // 4053 mode signals
        // ----------------------------------------------------------------
        reg         mux_sel_reg;        // 0=CH1, 1=CH2
        reg [7:0]   settle_cnt;        // settle delay counter
        reg         settling;           // high while waiting for 4053 to settle

        // Channel data registers
        reg [15:0]  ch1_hold, ch2_hold;
        reg         ch1_vld, ch2_vld;
        reg         den_pending;

        // When USE_4053=1: always read the same channel, toggle mux_sel
        // When USE_4053=0: alternate DRP addresses between 0x12 and 0x13
        reg         active_ch;          // only used in dual-channel mode

        wire [6:0]  ch_addr_dual = active_ch ? 7'h13 : 7'h12;

        assign drp_daddr = USE_4053 ? SINGLE_CH_ADDR : ch_addr_dual;
        assign drp_den   = USE_4053 ? (den_pending && !settling) : den_pending;

        assign ch1_data  = ch1_hold[15:4];
        assign ch1_valid = ch1_vld;
        assign ch2_data  = ch2_hold[15:4];
        assign ch2_valid = ch2_vld;
        assign mux_sel   = USE_4053 ? mux_sel_reg : 1'b0;

        always @(posedge clk or negedge rst_n) begin
            if (!rst_n) begin
                active_ch    <= 1'b0;
                mux_sel_reg  <= 1'b0;
                settle_cnt   <= 0;
                settling     <= 1'b0;
                ch1_hold     <= 16'h0800;
                ch2_hold     <= 16'h0800;
                ch1_vld      <= 1'b0;
                ch2_vld      <= 1'b0;
                den_pending  <= 1'b1;
            end else begin
                ch1_vld <= 1'b0;
                ch2_vld <= 1'b0;

                // --- Settle countdown for 4053 mode ---
                if (USE_4053 && settling) begin
                    if (settle_cnt == SETTLE_CYCLES - 1) begin
                        settling    <= 1'b0;
                        settle_cnt  <= 0;
                        // Now safe to start next conversion
                        den_pending <= 1'b1;
                    end else begin
                        settle_cnt <= settle_cnt + 1'b1;
                    end
                end

                // --- DEN: clear pending when asserted ---
                if (den_pending && drp_den) begin
                    den_pending <= 1'b0;
                end

                // --- DRDY: latch data and set up next conversion ---
                if (drp_drdy) begin
                    if (USE_4053) begin
                        // Route data to correct channel based on mux_sel
                        if (mux_sel_reg) begin
                            ch2_hold <= drp_do;
                            ch2_vld  <= 1'b1;
                        end else begin
                            ch1_hold <= drp_do;
                            ch1_vld  <= 1'b1;
                        end

                        // Toggle mux_sel for next channel
                        mux_sel_reg <= ~mux_sel_reg;

                        // Begin settle period before next DEN
                        settling    <= 1'b1;
                        settle_cnt  <= 0;
                        // den_pending will be set when settling completes

                    end else begin
                        // Original dual-channel mode
                        if (active_ch) begin
                            ch2_hold <= drp_do;
                            ch2_vld  <= 1'b1;
                        end else begin
                            ch1_hold <= drp_do;
                            ch1_vld  <= 1'b1;
                        end
                        active_ch    <= ~active_ch;
                        den_pending  <= 1'b1;
                    end
                end
            end
        end

    end
    endgenerate

endmodule
