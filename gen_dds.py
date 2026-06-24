import math
import os

#=============================================================================
# Generate bipolar-aware DDS core + sine LUT hex file
# Bipolar representation: 0x80 = 0V, 0x00 = -2V, 0xFF = +2V (symmetric +/-2V)
# DAC0832 bipolar output: Vout = Vref * (D - 128) / 128, with Vref ~= 2.016V
#=============================================================================

# --- Sine LUT: 1024 entries, centered exactly at 128, range 1..255 ---
vals = []
for i in range(1024):
    phase = 2 * math.pi * i / 1024
    vals.append(int(128 + 127 * math.sin(phase)))

# --- Write sine_lut.hex for $readmemh ---
hex_lines = []
for row in range(64):  # 1024 / 16 = 64 rows
    chunk = vals[row*16 : (row+1)*16]
    hex_lines.append(' '.join(f'{v:02x}' for v in chunk))

hex_path = os.path.join(os.path.dirname(os.path.abspath(__file__)),
                        'pocketscope_sim', 'pocketscope_sim.srcs', 'sources_1', 'new', 'sine_lut.hex')
with open(hex_path, 'w') as f:
    f.write('\n'.join(hex_lines))
print(f'Wrote {len(hex_lines)} lines to sine_lut.hex')

# --- Modulation LUT: 64 entries, centered at 0x80 (128), range 1..255, symmetric +/-2V ---
mod_vals = []
for i in range(64):
    phase = 2 * math.pi * i / 64
    mod_vals.append(int(128 + 127 * math.sin(phase)))

mod_hex_lines = []
for row in range(4):  # 64 / 16 = 4 rows
    chunk = mod_vals[row*16 : (row+1)*16]
    mod_hex_lines.append(' '.join(f'{v:02x}' for v in chunk))

mod_hex_path = os.path.join(os.path.dirname(os.path.abspath(__file__)),
                            'pocketscope_sim', 'pocketscope_sim.srcs', 'sources_1', 'new', 'mod_lut.hex')
with open(mod_hex_path, 'w') as f:
    f.write('\n'.join(mod_hex_lines))
print(f'Wrote {len(mod_hex_lines)} lines to mod_lut.hex')

# --- Generate dds_core.v (hex-file based, matching current architecture) ---
lines = []
lines.append('`timescale 1ns / 1ps')
lines.append('module dds_core')
lines.append('#(')
lines.append('    parameter PHASE_WIDTH = 24,')
lines.append('    parameter LUT_ADDR_W  = 10,')
lines.append('    parameter LUT_DATA_W  = 8')
lines.append(')')
lines.append('(')
lines.append('    input  wire                      clk,')
lines.append('    input  wire                      rst_n,')
lines.append('    input  wire [PHASE_WIDTH-1:0]    ftw,')
lines.append('    input  wire [1:0]                wave_type,')
lines.append('    output wire [LUT_DATA_W-1:0]     wave_out')
lines.append(');')
lines.append('')
lines.append('    localparam LUT_DEPTH = 1 << LUT_ADDR_W;')
lines.append('')
lines.append('    reg [PHASE_WIDTH-1:0] phase_acc = 0;')
lines.append('    always @(posedge clk or negedge rst_n) begin')
lines.append('        if (!rst_n)')
lines.append('            phase_acc <= 0;')
lines.append("        else if (ftw !== {PHASE_WIDTH{1'bx}})")
lines.append('            phase_acc <= phase_acc + ftw;')
lines.append('    end')
lines.append('')
lines.append('    wire [LUT_ADDR_W-1:0] lut_addr = phase_acc[PHASE_WIDTH-1 -: LUT_ADDR_W];')
lines.append('')
lines.append('    // Sine LUT: 0x80-centered bipolar values (loaded from hex file)')
lines.append('    reg [LUT_DATA_W-1:0] sine_lut [0:LUT_DEPTH-1];')
lines.append('    initial begin')
lines.append('        $readmemh("sine_lut.hex", sine_lut);')
lines.append('    end')
lines.append('')
lines.append('    wire [LUT_DATA_W-1:0] sine_val = sine_lut[lut_addr];')
lines.append('')
lines.append('    // Square wave: full symmetric swing +/-2V around 0x80 (255-128 = 128-1 = 127)')
lines.append("    wire [LUT_DATA_W-1:0] sqr_val = phase_acc[PHASE_WIDTH-1] ? 8'd255 : 8'd1;")
lines.append('')
lines.append('    // Triangle wave: symmetric +/-127 around 0x80, range 1-255')
lines.append('    // Uses 9-bit saturating arithmetic to keep center exactly at 128')
lines.append("    wire [8:0] tri_ramp_9 = {1'b0, phase_acc[PHASE_WIDTH-2 -: 8]};")
lines.append("    wire [8:0] tri_rising  = 9'd1 + tri_ramp_9;   // 1..256")
lines.append("    wire [8:0] tri_falling = 9'd256 - tri_ramp_9;  // 256..1")
lines.append('    wire [LUT_DATA_W-1:0] tri_val = phase_acc[PHASE_WIDTH-1]')
lines.append("        ? ((tri_falling > 9'd255) ? 8'd255 : tri_falling[7:0])")
lines.append("        : ((tri_rising  > 9'd255) ? 8'd255 : tri_rising[7:0] );")
lines.append('')
lines.append("    assign wave_out = (wave_type == 2'b01) ? sqr_val")
lines.append("                    : (wave_type == 2'b10) ? tri_val")
lines.append('                    : sine_val;')
lines.append('')
lines.append('endmodule')

verilog_path = os.path.join(os.path.dirname(os.path.abspath(__file__)),
                          'pocketscope_sim', 'pocketscope_sim.srcs', 'sources_1', 'new', 'dds_core.v')
with open(verilog_path, 'w') as f:
    f.write('\n'.join(lines))
print(f'Wrote {len(lines)} lines to dds_core.v')
