`timescale 1ns / 1ps
//=============================================================================
// UI Controller — button debounce, mode decoding, parameter adjustment
//=============================================================================
// Switch assignment:
//   sw[1:0]   = main mode (00=sig gen, 01=scope, 10=lissajous, 11=kaleidoscope)
//   sw[4:2]   = sub-mode / wave type in sig-gen mode
//   sw[7:5]   = frequency coarse range
//   DIP[7:0]  = frequency fine (0-255 * 20Hz steps)
//
// Button assignment:
//   PB0 = amplitude up   (+10)
//   PB1 = amplitude down (-10)
//   PB2 = mod depth up   (+16)
//   PB3 = mod depth down (-16)
//   PB4 = scope trigger level (+10, wrap)
//=============================================================================

module ui_ctrl
#(
    parameter PHASE_WIDTH = 24
)
(
    input  wire                      clk,
    input  wire                      rst_n,
    input  wire [4:0]                btn,
    input  wire [7:0]                sw,
    input  wire [7:0]                sw_dip,
    // Modes
    output reg  [1:0]                device_mode,
    output reg  [2:0]                sig_gen_submode,
    output reg  [1:0]                mod_type,
    output reg                       mod_enable,
    // Parameters
    output reg  [PHASE_WIDTH-1:0]    frequency_ftw,
    output reg  [7:0]                amplitude,
    output reg  [7:0]                mod_depth,
    // Scope
    output reg  [2:0]                scope_timebase,
    output reg  [7:0]                scope_trigger_level
);

    //=========================================================================
    // Button debounce — integration / saturating-counter method
    //
    // Each button has a 17-bit counter that saturates at 0 and DB_MAX.
    // When input is high, counter increments; when low, it decrements.
    // The stable output changes only when the counter saturates at either end.
    // This requires ~5.2ms of NET high time (at 25MHz) to register a press,
    // and the same for release. Bounces self-cancel — a 100ns glitch has
    // negligible effect on a counter that spans 0..131071.
    //
    // This is far more robust than the previous "must-stay-different-for-10ms"
    // approach, which rejected valid presses whenever a single bounce-back
    // reset the timer.
    //=========================================================================
    localparam DB_BITS = 17;
    localparam DB_MAX  = (1 << DB_BITS) - 1;   // 131071 ≈ 5.24ms @ 25MHz

    reg [1:0]              btn_sync [0:4];       // 2-stage synchronizer per button
    reg [DB_BITS-1:0]      db_cnt   [0:4];       // integration counter
    reg                    btn_stable [0:4];      // debounced output
    reg                    btn_prev [0:4];        // previous stable for edge detect
    wire                   btn_rise [0:4];
    wire                   btn_fall [0:4];

    genvar gi;
    generate for (gi = 0; gi < 5; gi = gi + 1) begin : debounce_block
        // ---- 2-stage synchronizer ----
        always @(posedge clk or negedge rst_n) begin
            if (!rst_n) begin
                btn_sync[gi] <= 2'b00;
            end else begin
                btn_sync[gi] <= {btn_sync[gi][0], btn[gi]};
            end
        end

        // ---- Integration counter + stable output ----
        always @(posedge clk or negedge rst_n) begin
            if (!rst_n) begin
                db_cnt[gi]      <= 0;
                btn_stable[gi]  <= 1'b0;
            end else begin
                // saturating up/down based on synchronized input
                if (btn_sync[gi][1]) begin
                    if (db_cnt[gi] < DB_MAX)
                        db_cnt[gi] <= db_cnt[gi] + 1'b1;
                end else begin
                    if (db_cnt[gi] > 0)
                        db_cnt[gi] <= db_cnt[gi] - 1'b1;
                end

                // update stable output only at saturation
                if (db_cnt[gi] == DB_MAX)
                    btn_stable[gi] <= 1'b1;
                else if (db_cnt[gi] == 0)
                    btn_stable[gi] <= 1'b0;
            end
        end

        // ---- Edge detection ----
        always @(posedge clk or negedge rst_n) begin
            if (!rst_n)
                btn_prev[gi] <= 1'b0;
            else
                btn_prev[gi] <= btn_stable[gi];
        end

        assign btn_rise[gi] = btn_stable[gi] && !btn_prev[gi];
        assign btn_fall[gi] = !btn_stable[gi] && btn_prev[gi];
    end endgenerate

    //=========================================================================
    // Switch debounce — integration filter for slide switches and DIP switches
    //
    // Slide switches don't bounce like pushbuttons, but they can have brief
    // contact interruptions during movement or from mechanical vibration.
    // Without filtering, a single glitch on sw[4:2] could momentarily switch
    // waveform type or enable/disable modulation, causing "superimposed"
    // waveforms on the DAC output.
    //
    // 8-bit saturating counter per switch bit gives ~10µs filter time at
    // 25MHz — fast enough to feel instant, long enough to reject noise.
    //=========================================================================
    localparam SW_DB_BITS = 8;
    localparam SW_DB_MAX  = (1 << SW_DB_BITS) - 1;  // 255 ≈ 10.2µs @ 25MHz

    reg [1:0]              sw_sync [0:7];        // 2-stage sync per switch bit
    reg [SW_DB_BITS-1:0]   sw_dbcnt [0:7];       // debounce counter
    reg                    sw_filtered [0:7];     // filtered switch output

    reg [1:0]              dip_sync [0:7];
    reg [SW_DB_BITS-1:0]   dip_dbcnt [0:7];
    reg                    dip_filtered [0:7];

    genvar si;
    generate for (si = 0; si < 8; si = si + 1) begin : switch_debounce

        // ---- SW[si] ----
        always @(posedge clk or negedge rst_n) begin
            if (!rst_n) begin
                sw_sync[si]   <= 2'b00;
                sw_dbcnt[si]  <= 0;
                sw_filtered[si] <= 1'b0;
            end else begin
                sw_sync[si] <= {sw_sync[si][0], sw[si]};

                if (sw_sync[si][1])
                    sw_dbcnt[si] <= (sw_dbcnt[si] < SW_DB_MAX) ? sw_dbcnt[si] + 1'b1 : sw_dbcnt[si];
                else
                    sw_dbcnt[si] <= (sw_dbcnt[si] > 0) ? sw_dbcnt[si] - 1'b1 : sw_dbcnt[si];

                if (sw_dbcnt[si] == SW_DB_MAX)
                    sw_filtered[si] <= 1'b1;
                else if (sw_dbcnt[si] == 0)
                    sw_filtered[si] <= 1'b0;
            end
        end

        // ---- DIP[si] ----
        always @(posedge clk or negedge rst_n) begin
            if (!rst_n) begin
                dip_sync[si]   <= 2'b00;
                dip_dbcnt[si]  <= 0;
                dip_filtered[si] <= 1'b0;
            end else begin
                dip_sync[si] <= {dip_sync[si][0], sw_dip[si]};

                if (dip_sync[si][1])
                    dip_dbcnt[si] <= (dip_dbcnt[si] < SW_DB_MAX) ? dip_dbcnt[si] + 1'b1 : dip_dbcnt[si];
                else
                    dip_dbcnt[si] <= (dip_dbcnt[si] > 0) ? dip_dbcnt[si] - 1'b1 : dip_dbcnt[si];

                if (dip_dbcnt[si] == SW_DB_MAX)
                    dip_filtered[si] <= 1'b1;
                else if (dip_dbcnt[si] == 0)
                    dip_filtered[si] <= 1'b0;
            end
        end
    end endgenerate

    // Reconstruct filtered 8-bit switch buses
    wire [7:0] sw_f     = {sw_filtered[7], sw_filtered[6], sw_filtered[5],
                           sw_filtered[4], sw_filtered[3], sw_filtered[2],
                           sw_filtered[1], sw_filtered[0]};
    wire [7:0] sw_dip_f = {dip_filtered[7], dip_filtered[6], dip_filtered[5],
                           dip_filtered[4], dip_filtered[3], dip_filtered[2],
                           dip_filtered[1], dip_filtered[0]};

    //=========================================================================
    // Frequency: sw[7:5] coarse range + DIP[7:0] fine, 20Hz resolution
    // Clamped to 100Hz ~ 10kHz per specification
    // Uses filtered switch values to prevent glitch-induced frequency jumps
    //=========================================================================
    wire [2:0]  coarse         = sw_f[7:5];
    wire [15:0] freq_unclamped =
        (coarse == 3'd0) ? (16'd100  + {8'b0, sw_dip_f} * 16'd20) :
        (coarse == 3'd1) ? (16'd2000 + {8'b0, sw_dip_f} * 16'd20) :
        (coarse == 3'd2) ? (16'd4000 + {8'b0, sw_dip_f} * 16'd20) :
        (coarse == 3'd3) ? (16'd6000 + {8'b0, sw_dip_f} * 16'd20) :
        (coarse == 3'd4) ? (16'd8000 + {8'b0, sw_dip_f} * 16'd20) :
        16'd1000;   // fallback

    wire [15:0] freq_clamped =
        (freq_unclamped < 16'd100)   ? 16'd100   :
        (freq_unclamped > 16'd10000) ? 16'd10000 :
        freq_unclamped;

    // Register frequency in Hz (one-cycle latency, negligible for UI)
    reg [15:0] freq_hz;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            freq_hz <= 16'd1000;
        else
            freq_hz <= freq_clamped;
    end

    // FTW = freq_hz * 2^PHASE_WIDTH / Fclk
    //     = freq_hz * 2^24 / 25_000_000
    //     = freq_hz * 16_777_216 / 25_000_000
    wire [47:0] ftw_full = (freq_hz * 48'd16777216) / 48'd25000000;

    //=========================================================================
    // Main register block — switch decoding + button actions
    //=========================================================================
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            device_mode         <= 2'b00;
            sig_gen_submode     <= 3'b000;
            mod_type            <= 2'b00;
            mod_enable          <= 1'b0;
            amplitude           <= 8'hFF;
            mod_depth           <= 8'h80;
            scope_timebase      <= 3'd3;
            scope_trigger_level <= 8'd128;
            frequency_ftw       <= 0;
        end else begin
            // ---- Switch-driven settings (use filtered switches) ----
            device_mode     <= sw_f[1:0];
            sig_gen_submode <= sw_f[4:2];

            // Frequency tuning word from registered Hz value
            frequency_ftw <= ftw_full[PHASE_WIDTH-1:0];

            // Modulation decode from filtered sub-mode switches
            case (sw_f[4:2])
                3'b011: begin
                    mod_type   <= 2'b00;   // AM
                    mod_enable <= 1'b1;
                end
                3'b100: begin
                    mod_type   <= 2'b01;   // FM
                    mod_enable <= 1'b1;
                end
                3'b101: begin
                    mod_type   <= 2'b10;   // SPWM
                    mod_enable <= 1'b1;
                end
                default: begin
                    mod_enable <= 1'b0;
                end
            endcase

            // ---- Button actions (edge-triggered, one action per press) ----
            // PB0: amplitude +10  (clamped to 255 max)
            if (btn_rise[0] && amplitude <= 8'd245)
                amplitude <= amplitude + 8'd10;
            else if (btn_rise[0])
                amplitude <= 8'd255;

            // PB1: amplitude -10  (clamped to 0 min)
            if (btn_rise[1] && amplitude >= 8'd10)
                amplitude <= amplitude - 8'd10;
            else if (btn_rise[1])
                amplitude <= 8'd0;

            // PB2: mod depth +16
            if (btn_rise[2] && mod_depth <= 8'd239)
                mod_depth <= mod_depth + 8'd16;
            else if (btn_rise[2])
                mod_depth <= 8'd255;

            // PB3: mod depth -16
            if (btn_rise[3] && mod_depth >= 8'd16)
                mod_depth <= mod_depth - 8'd16;
            else if (btn_rise[3])
                mod_depth <= 8'd0;

            // PB4: scope trigger level +10 (wraps around)
            if (btn_rise[4]) begin
                if (scope_trigger_level < 8'd245)
                    scope_trigger_level <= scope_trigger_level + 8'd10;
                else
                    scope_trigger_level <= 8'd10;
            end
        end
    end

endmodule
