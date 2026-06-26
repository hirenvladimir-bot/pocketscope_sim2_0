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
// XADC Timing (XC7A35T, 100MHz DCLK, continuous mode):
//   ADCCLK = DCLK/2 = 50MHz (20ns period)
//   Conversion time = ~26 ADCCLK cycles ≈ 520ns  (UG480: 22-26 cycles)
//   4053 t_on(max) = 60ns, settle margin = 100ns (10 DCLK cycles)
//   Total per-sample = 520ns + 100ns settle = 620ns
//   Per-channel rate  ≈ 1/(2×620ns) ≈ 806 kSPS total, ~403 kSPS per channel
//
// Extension board front-end (EGO1_Oscilloscope_Gen):
//   BNC → 10kΩ + 100kΩ trimmer → MCP6002 (G=1.1×) → 74HC4053 → XADC VAUXP2
//   VBIAS = 3.3V×(10k/(56k+10k)) ≈ 0.5V, op-amp DC out ≈ 0.55V
//   XADC 12-bit 0-1V → code uses adc[11:4] (8-bit, 0-255)
//   ADC LSB (8-bit) = 1V/256 = 3.90625mV at XADC input
//   Front-end gain ≈ 0.909×1.1 ≈ 1.0 at max trimmer → ~3.91mV/LSB at BNC
//
// SIM_MODE=1 bypasses XADC for pure-digital simulation.

module xadc_reader
#(
    parameter SIM_MODE       = 1,
    parameter USE_4053       = 0,        // 0=dual XADC channel, 1=single ch + 4053 mux
    parameter SINGLE_CH_ADDR = 7'h12,    // XADC DRP addr when USE_4053=1 (VAUXP[2], J5 pins 9-10)
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
    output wire          mux_sel,         // 0=CH1 routed to ADC, 1=CH2 routed to ADC
    // Sample rate measurement (debug)
    output reg  [15:0]   sample_rate_hz,  // CH1 samples per second
    output reg           sample_rate_update, // pulsed when sample_rate_hz updates
    // DRP handshake debug outputs (for ILA monitoring)
    output wire          dbg_drp_drdy,    // DRP data-ready from XADC
    output wire          dbg_drp_den,     // DRP enable to XADC
    output wire          dbg_settling,    // 4053 settle wait state
    output wire          dbg_den_pending, // DEN pending flag
    output wire          dbg_startup_done // XADC post-reset calibration complete
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
        // Debug outputs: simulation mode has no real DRP, tie low
        assign dbg_drp_drdy    = sim_vld1 | sim_vld2;  // emulate DRDY on valid
        assign dbg_drp_den     = 1'b0;                  // no real DRP
        assign dbg_settling    = 1'b0;
        assign dbg_den_pending = 1'b0;
        assign dbg_startup_done = 1'b1;                 // always ready in sim

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
            // INIT_40: Configuration Register #0
            //   bit12 (CAL1)  = 1 -> enable offset calibration
            //   bit5  (CAL0)  = 1 -> enable gain calibration
            //   bit4  (CHSEL) = 1 -> enable sequencer mode (required for VAUXP sampling)
            //   bits[3:0] (SEQ) = 0010 -> continuous sequencer cycling
            //   FIX: was 0x1012 → CHSEL was still 0 (single-ch mode). Now 0x1032
            //        sets both CAL0 and CHSEL. Required so sequencer uses INIT_48
            //        channel enables to sample VAUXP[2] instead of a default channel.
            .INIT_40(16'h1032),
            .INIT_41(16'h2000),
            .INIT_42(16'h0000),
            // Enable VAUXP[2] in sequencer (48h: VAUXP[7:0] channel enable)
            // Bit 2 = 1 -> VAUXP[2]/VAUXN[2] IS sampled by the sequencer.
            // REQUIRED for 4053 mux mode: both CH1/CH2 via single VAUXP2 ch.
            .INIT_48(16'h0004),
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

        // Startup delay: XADC needs ~4ms at 100MHz for post-reset auto-calibration
        // (UG480: calibration completes ~4ms after DCLK stable).
        // 500,000 cycles = 5ms at 100MHz — provides safe margin.
        // If DEN is sent during calibration, DRDY never asserts and the FSM hangs
        // permanently. This extended delay prevents that lockup.
        localparam STARTUP_MAX = 19'd500_000;
        reg [18:0]  startup_cnt;
        wire        startup_done = (startup_cnt == STARTUP_MAX);

        // DRDY timeout watchdog: if DRDY doesn't arrive within ~10µs after DEN,
        // re-trigger DEN. Prevents permanent FSM hang if XADC misses a DEN pulse.
        localparam DRDY_TIMEOUT = 10'd1000;   // 1000 cycles = 10µs at 100MHz
        reg [9:0]   drdy_timeout_cnt;
        reg         den_sent;                 // flag: DEN was issued, waiting for DRDY

        wire [6:0]  ch_addr_dual = active_ch ? 7'h13 : 7'h12;

        assign drp_daddr = USE_4053 ? SINGLE_CH_ADDR : ch_addr_dual;
        assign drp_den   = USE_4053 ? (den_pending && !settling && startup_done) : (den_pending && startup_done);

        assign ch1_data  = ch1_hold[15:4];
        assign ch1_valid = ch1_vld;
        assign ch2_data  = ch2_hold[15:4];
        assign ch2_valid = ch2_vld;
        assign mux_sel   = USE_4053 ? mux_sel_reg : 1'b0;

        always @(posedge clk or negedge rst_n) begin
            if (!rst_n) begin
                active_ch        <= 1'b0;
                mux_sel_reg      <= 1'b0;  // mux forced LOW → CH1 selected
                settle_cnt       <= 0;
                settling         <= 1'b0;
                ch1_hold         <= 16'h0800;
                ch2_hold         <= 16'h0800;
                ch1_vld          <= 1'b0;
                ch2_vld          <= 1'b0;
                den_pending      <= 1'b0;
                den_sent         <= 1'b0;
                startup_cnt      <= 0;
                drdy_timeout_cnt <= 0;
            end else begin
                ch1_vld <= 1'b0;
                ch2_vld <= 1'b0;

                // --- Startup delay: count up to STARTUP_MAX (~5ms) before DRP access ---
                // XADC needs ~4ms post-reset calibration. During calibration,
                // DRDY does NOT assert, so we must wait before first DEN.
                if (!startup_done) begin
                    startup_cnt <= startup_cnt + 1'b1;
                    if (startup_cnt == STARTUP_MAX - 1) begin
                        // Startup complete — trigger first DRP read
                        den_pending <= 1'b1;
                        den_sent    <= 1'b0;
                    end
                end

                // --- Settle countdown for 4053 mode ---
                if (USE_4053 && settling) begin
                    if (settle_cnt == SETTLE_CYCLES - 1) begin
                        settling    <= 1'b0;
                        settle_cnt  <= 0;
                        // Now safe to start next conversion
                        den_pending <= 1'b1;
                        den_sent    <= 1'b0;
                    end else begin
                        settle_cnt <= settle_cnt + 1'b1;
                    end
                end

                // --- DEN: assert pending, track when sent ---
                if (den_pending && drp_den) begin
                    den_pending <= 1'b0;
                    den_sent    <= 1'b1;
                    drdy_timeout_cnt <= 0;
                end

                // --- DRDY timeout watchdog: re-issue DEN if no response ---
                // When DEN was sent but DRDY never comes (e.g., XADC still
                // calibrating, missed DEN pulse), retry after timeout.
                // This prevents permanent FSM hang.
                if (den_sent && !drp_drdy) begin
                    if (drdy_timeout_cnt == DRDY_TIMEOUT - 1) begin
                        // Timeout: DRDY never responded — re-trigger DEN
                        den_pending      <= 1'b1;
                        den_sent         <= 1'b0;
                        drdy_timeout_cnt <= 0;
                    end else begin
                        drdy_timeout_cnt <= drdy_timeout_cnt + 1'b1;
                    end
                end

                // --- DRDY: latch data and set up next conversion ---
                if (drp_drdy) begin
                    den_sent <= 1'b0;  // clear sent flag, response received
                    if (USE_4053) begin
                        // Route data to correct channel based on mux_sel
                        if (mux_sel_reg) begin
                            ch2_hold <= drp_do;
                            ch2_vld  <= 1'b1;
                        end else begin
                            ch1_hold <= drp_do;
                            ch1_vld  <= 1'b1;
                        end

                        // Toggle mux_sel for next channel (CH1↔CH2 alternating)
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
                        den_sent     <= 1'b0;
                    end
                end
            end
        end

        // Debug outputs: expose internal DRP handshake signals
        assign dbg_drp_drdy    = drp_drdy;
        assign dbg_drp_den     = drp_den;
        assign dbg_settling    = settling;
        assign dbg_den_pending = den_pending;
        assign dbg_startup_done = startup_done;

    end
    endgenerate

    //=========================================================================
    // Sample Rate Counter (common to both sim_mode and hw_mode)
    // Counts ch1_valid pulses over a 1-second gate at 100MHz.
    // Result = effective CH1 sampling rate in Hz.
    //=========================================================================
    localparam GATE_1SEC = 27'd100_000_000;  // 1 second at 100MHz

    reg [26:0] sr_gate_cnt;        // 1-second gate counter
    reg [31:0] sr_pulse_cnt;       // CH1 valid pulse counter
    reg [3:0]  sr_update_stretch;  // update flag stretch counter

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            sr_gate_cnt         <= 0;
            sr_pulse_cnt        <= 0;
            sample_rate_hz      <= 0;
            sample_rate_update  <= 1'b0;
            sr_update_stretch   <= 0;
        end else begin
            // Default: deassert update after stretch completes
            if (sample_rate_update) begin
                if (sr_update_stretch == 4'd14) begin
                    sample_rate_update <= 1'b0;
                    sr_update_stretch  <= 0;
                end else begin
                    sr_update_stretch <= sr_update_stretch + 1'b1;
                end
            end

            // Count ch1_valid pulses
            if (ch1_valid)
                sr_pulse_cnt <= sr_pulse_cnt + 1'b1;

            // 1-second gate
            if (sr_gate_cnt == GATE_1SEC - 1) begin
                sr_gate_cnt    <= 0;
                sample_rate_hz <= sr_pulse_cnt[15:0];
                sr_pulse_cnt   <= 0;
                // Strobe update (stretched to ~15 cycles = 150ns > 2x 25MHz period)
                sample_rate_update <= 1'b1;
                sr_update_stretch  <= 0;
            end else begin
                sr_gate_cnt <= sr_gate_cnt + 1'b1;
            end
        end
    end

endmodule
