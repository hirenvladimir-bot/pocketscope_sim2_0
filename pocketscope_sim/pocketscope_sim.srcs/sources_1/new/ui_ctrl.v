`timescale 1ns / 1ps
// UI Controller: button debounce, mode FSM, parameter adjustment
//
// Switch assignment:
//   sw[1:0]   = main mode (00=sig gen, 01=scope, 10=lissajous)
//   sw[4:2]   = sub-mode / wave type
//   sw[7:5]   = frequency coarse range
//   DIP[7:0]  = frequency fine (0-255 * 20Hz steps)
//
// Button assignment:
//   PB0 = amplitude up (+10)
//   PB1 = amplitude down (-10)
//   PB2 = mod depth up
//   PB3 = mod depth down
//   PB4 = scope trigger level adjust

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

    // Button debounce (10ms at 25MHz = 250k cycles)
    localparam DB_MAX = 250000;
    reg [19:0] db_cnt [0:4];
    reg [4:0]  btn_sync1, btn_sync2, btn_stable, btn_prev;
    wire [4:0] btn_rise;

    genvar gi;
    generate for (gi = 0; gi < 5; gi = gi + 1) begin : db
        always @(posedge clk or negedge rst_n) begin
            if (!rst_n) begin
                btn_sync1[gi]  <= 0;
                btn_sync2[gi]  <= 0;
                btn_stable[gi] <= 0;
                db_cnt[gi]     <= 0;
            end else begin
                btn_sync1[gi] <= btn[gi];
                btn_sync2[gi] <= btn_sync1[gi];
                if (btn_sync2[gi] != btn_stable[gi]) begin
                    if (db_cnt[gi] == DB_MAX - 1) begin
                        btn_stable[gi] <= btn_sync2[gi];
                        db_cnt[gi]     <= 0;
                    end else
                        db_cnt[gi] <= db_cnt[gi] + 1'b1;
                end else
                    db_cnt[gi] <= 0;
            end
        end
    end endgenerate

    always @(posedge clk) btn_prev <= btn_stable;
    assign btn_rise = btn_stable & ~btn_prev;

    // Frequency: sw[7:5] coarse + DIP fine, 20Hz resolution
    reg [15:0] freq_hz;
    wire [2:0] coarse = sw[7:5];

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            freq_hz <= 16'd1000;
        else begin
            case (coarse)
                3'd0: freq_hz <= 16'd100  + {8'b0, sw_dip} * 16'd20;
                3'd1: freq_hz <= 16'd2000 + {8'b0, sw_dip} * 16'd20;
                3'd2: freq_hz <= 16'd4000 + {8'b0, sw_dip} * 16'd20;
                3'd3: freq_hz <= 16'd6000 + {8'b0, sw_dip} * 16'd20;
                3'd4: freq_hz <= 16'd8000 + {8'b0, sw_dip} * 16'd20;
                default: freq_hz <= 16'd1000;
            endcase
        end
    end

    // FTW = freq * 2^24 / 100e6 = freq * 0.16777216
    wire [31:0] ftw_full = (freq_hz * 32'd16777) / 32'd10000;
    always @(posedge clk) frequency_ftw <= ftw_full[PHASE_WIDTH-1:0];

    // Main FSM
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
        end else begin
            device_mode     <= sw[1:0];
            sig_gen_submode <= sw[4:2];

            // Modulation: sw[4:2]=011(AM), 100(FM), 101(SPWM)
            case (sw[4:2])
                3'b011: begin mod_type <= 2'b00; mod_enable <= 1'b1; end
                3'b100: begin mod_type <= 2'b01; mod_enable <= 1'b1; end
                3'b101: begin mod_type <= 2'b10; mod_enable <= 1'b1; end
                default: mod_enable <= 1'b0;
            endcase

            // Button adjustments
            if (btn_rise[0] && amplitude < 8'd250)
                amplitude <= amplitude + 8'd10;
            if (btn_rise[1] && amplitude > 8'd10)
                amplitude <= amplitude - 8'd10;
            if (btn_rise[2] && mod_depth < 8'd240)
                mod_depth <= mod_depth + 8'd16;
            if (btn_rise[3] && mod_depth > 8'd16)
                mod_depth <= mod_depth - 8'd16;
            if (btn_rise[4])
                scope_trigger_level <= scope_trigger_level + 8'd10;
        end
    end

endmodule
