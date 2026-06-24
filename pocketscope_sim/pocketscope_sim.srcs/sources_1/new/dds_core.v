`timescale 1ns / 1ps
module dds_core
#(
    parameter PHASE_WIDTH = 24,
    parameter LUT_ADDR_W  = 10,
    parameter LUT_DATA_W  = 8
)
(
    input  wire                      clk,
    input  wire                      rst_n,
    input  wire [PHASE_WIDTH-1:0]    ftw,
    input  wire [1:0]                wave_type,
    output wire [LUT_DATA_W-1:0]     wave_out
);

    localparam LUT_DEPTH = 1 << LUT_ADDR_W;

    reg [PHASE_WIDTH-1:0] phase_acc = 0;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            phase_acc <= 0;
        else if (ftw !== {PHASE_WIDTH{1'bx}})
            phase_acc <= phase_acc + ftw;
    end

    wire [LUT_ADDR_W-1:0] lut_addr = phase_acc[PHASE_WIDTH-1 -: LUT_ADDR_W];

    // Sine LUT: 0x80-centered bipolar values (loaded from hex file)
    reg [LUT_DATA_W-1:0] sine_lut [0:LUT_DEPTH-1];
    initial begin
        $readmemh("sine_lut.hex", sine_lut);
    end

    wire [LUT_DATA_W-1:0] sine_val = sine_lut[lut_addr];

    // Square wave: full symmetric swing +/-2V around 0x80 (255-128 = 128-1 = 127)
    wire [LUT_DATA_W-1:0] sqr_val = phase_acc[PHASE_WIDTH-1] ? 8'd255 : 8'd1;

    // Triangle wave: symmetric +/-127 around 0x80, range 1-255
    // Uses 9-bit saturating arithmetic to keep center exactly at 128
    wire [8:0] tri_ramp_9 = {1'b0, phase_acc[PHASE_WIDTH-2 -: 8]};
    wire [8:0] tri_rising  = 9'd1 + tri_ramp_9;   // 1..256
    wire [8:0] tri_falling = 9'd256 - tri_ramp_9;  // 256..1
    wire [LUT_DATA_W-1:0] tri_val = phase_acc[PHASE_WIDTH-1]
        ? ((tri_falling > 9'd255) ? 8'd255 : tri_falling[7:0])
        : ((tri_rising  > 9'd255) ? 8'd255 : tri_rising[7:0] );

    assign wave_out = (wave_type == 2'b01) ? sqr_val
                    : (wave_type == 2'b10) ? tri_val
                    : sine_val;

endmodule