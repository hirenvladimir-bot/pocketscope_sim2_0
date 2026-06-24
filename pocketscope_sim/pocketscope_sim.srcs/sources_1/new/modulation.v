`timescale 1ns / 1ps
module modulation
#(parameter PHASE_WIDTH = 24)
(
    input wire clk, rst_n,
    input wire [1:0] mod_type,
    input wire mod_enable,
    input wire [PHASE_WIDTH-1:0] base_ftw,
    input wire [7:0] carrier_in, mod_depth,
    output wire [PHASE_WIDTH-1:0] fm_ftw_out,
    output wire [7:0] signal_out
);
    localparam MOD_FTW = 24'd327;
    reg [PHASE_WIDTH-1:0] mod_phase = 0;
    wire [5:0] mod_addr = mod_phase[PHASE_WIDTH-1 -: 6];
    reg [7:0] mod_lut [0:63];
    initial $readmemh("mod_lut.hex", mod_lut);
    wire [7:0] mod_wave = mod_lut[mod_addr];

    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) mod_phase <= 0;
        else mod_phase <= mod_phase + MOD_FTW;
    end

    localparam TRI_MAX = 1023;  // symmetric triangle: 0-1023
    reg [9:0] tri_cnt = 0; reg tri_dir = 0;
    // Center-symmetric triangle: range 1-255, centered at 128 (0x80)
    // Add 1 and saturate at 255 to prevent wraparound
    wire [8:0] tri_shifted = {1'b0, tri_cnt[9], tri_cnt[8:2]} + 9'd1;
    wire [7:0] tri_val = (tri_shifted > 9'd255) ? 8'd255 : tri_shifted[7:0];
    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin tri_cnt<=0; tri_dir<=0; end
        else begin
            if(!tri_dir) begin
                if(tri_cnt==TRI_MAX) begin tri_dir<=1; tri_cnt<=TRI_MAX-1; end
                else tri_cnt<=tri_cnt+1;
            end else begin
                if(tri_cnt==0) begin tri_dir<=0; tri_cnt<=1; end
                else tri_cnt<=tri_cnt-1;
            end
        end
    end

    reg [PHASE_WIDTH-1:0] fm_ftw_reg = 0;
    reg [7:0] sig_out_reg = 0;
    assign fm_ftw_out = fm_ftw_reg;
    assign signal_out = sig_out_reg;

    wire signed [PHASE_WIDTH:0] fm_dev = $signed({1'b0, mod_depth, 5'b0}) *
        $signed({1'b0, mod_wave}) / $signed(9'd256);

    // Bipolar AM: modulate deviation from 0x80 center, preserve DC
    // Formula: out = 128 + (carrier-128) * mod_factor / 128
    //   where mod_factor = 128 + mod_depth * (mod_wave-128) / 256
    wire signed [8:0]  am_mod_dev   = $signed({1'b0, mod_wave}) - 9'sd128;
    wire signed [8:0]  am_depth_s   = $signed({1'b0, mod_depth});
    wire signed [17:0] am_depth_mul = am_mod_dev * am_depth_s;
    wire [7:0]         am_mod_fact  = 8'd128 + am_depth_mul[15:8];
    wire signed [8:0]  am_carr_dev  = $signed({1'b0, carrier_in}) - 9'sd128;
    wire signed [17:0] am_prod      = am_carr_dev * $signed({1'b0, am_mod_fact});
    wire [7:0]         am_result    = 8'd128 + am_prod[15:8];

    always @(*) begin
        if(!mod_enable) begin fm_ftw_reg=base_ftw; sig_out_reg=carrier_in; end
        else begin
            case(mod_type)
                2'b00: begin fm_ftw_reg = base_ftw; sig_out_reg = am_result; end
                2'b01: begin fm_ftw_reg=base_ftw+fm_dev[PHASE_WIDTH-1:0]; sig_out_reg=carrier_in; end
                2'b10: begin fm_ftw_reg=base_ftw; sig_out_reg=(carrier_in>tri_val)?8'hFF:8'h00; end
                default: begin fm_ftw_reg=base_ftw; sig_out_reg=carrier_in; end
            endcase
        end
    end
endmodule
