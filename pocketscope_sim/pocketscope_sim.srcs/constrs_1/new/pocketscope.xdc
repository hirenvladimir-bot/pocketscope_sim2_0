#=============================================================================
# PocketScope - EGO1 (XC7A35T-1CSG324C) Pin Constraints
# Matches top.v port names (sys_clk, sw_in, led_speed, loop_tx/rx, etc.)
#=============================================================================

# System Clock: 100MHz
set_property PACKAGE_PIN P17 [get_ports sys_clk]
set_property IOSTANDARD LVCMOS33 [get_ports sys_clk]
create_clock -period 10.000 -name sys_clk_pin -waveform {0.000 5.000} [get_ports sys_clk]

# Generated 25MHz clock (clk_div_25m divide-by-4 from sys_clk, BUFG output)
# Rising edges of clk_25m occur at sys_clk edges 3, 7, 11, ... (period = 40ns)
#   sys_clk 100MHz: edge1(0ns↑), edge2(5ns↓), edge3(10ns↑), edge4(15ns↓),
#                     edge5(20ns↑), edge6(25ns↓), edge7(30ns↑), edge8(35ns↓),
#                     edge9(40ns↑), edge10(45ns↓), edge11(50ns↑)
#   clk_25m: rising at edge3(10ns) → falling at edge7(30ns) → rising at edge11(50ns)
create_generated_clock -name clk_25m -source [get_ports sys_clk] \
    -edges {3 7 11} [get_nets clk_25m]

# CDC paths between sys_clk (100MHz) and clk_25m (25MHz) domains are properly
# synchronized in RTL (pulse stretching + 2-stage synchronizer). Declare clock
# groups as asynchronous to prevent STA from reporting false timing violations
# on cross-domain data paths.
set_clock_groups -asynchronous \
    -group [get_clocks sys_clk_pin] \
    -group [get_clocks clk_25m]

# Reset
set_property PACKAGE_PIN P15 [get_ports rst_n]
set_property IOSTANDARD LVCMOS33 [get_ports rst_n]

#=============================================================================
# VGA (12-bit: R[3:0], G[3:0], B[3:0])
#=============================================================================
set_property PACKAGE_PIN F5  [get_ports {vga_r[0]}]
set_property PACKAGE_PIN C6  [get_ports {vga_r[1]}]
set_property PACKAGE_PIN C5  [get_ports {vga_r[2]}]
set_property PACKAGE_PIN B7  [get_ports {vga_r[3]}]
set_property PACKAGE_PIN B6  [get_ports {vga_g[0]}]
set_property PACKAGE_PIN A6  [get_ports {vga_g[1]}]
set_property PACKAGE_PIN A5  [get_ports {vga_g[2]}]
set_property PACKAGE_PIN D8  [get_ports {vga_g[3]}]
set_property PACKAGE_PIN C7  [get_ports {vga_b[0]}]
set_property PACKAGE_PIN E6  [get_ports {vga_b[1]}]
set_property PACKAGE_PIN E5  [get_ports {vga_b[2]}]
set_property PACKAGE_PIN E7  [get_ports {vga_b[3]}]
set_property PACKAGE_PIN D7  [get_ports hsync]
set_property PACKAGE_PIN C4  [get_ports vsync]

set_property IOSTANDARD LVCMOS33 [get_ports {vga_r[*]}]
set_property IOSTANDARD LVCMOS33 [get_ports {vga_g[*]}]
set_property IOSTANDARD LVCMOS33 [get_ports {vga_b[*]}]
set_property IOSTANDARD LVCMOS33 [get_ports hsync]
set_property IOSTANDARD LVCMOS33 [get_ports vsync]

#=============================================================================
# DAC0832 (EGO1 v2.2 manual, Section 13, J2 connector)
#=============================================================================
set_property PACKAGE_PIN T8  [get_ports {dac_d[0]}]
set_property PACKAGE_PIN R8  [get_ports {dac_d[1]}]
set_property PACKAGE_PIN T6  [get_ports {dac_d[2]}]
set_property PACKAGE_PIN R7  [get_ports {dac_d[3]}]
set_property PACKAGE_PIN U6  [get_ports {dac_d[4]}]
set_property PACKAGE_PIN U7  [get_ports {dac_d[5]}]
set_property PACKAGE_PIN V9  [get_ports {dac_d[6]}]
set_property PACKAGE_PIN U9  [get_ports {dac_d[7]}]
set_property PACKAGE_PIN R5  [get_ports dac_ile]
set_property PACKAGE_PIN N6  [get_ports dac_cs_n]
set_property PACKAGE_PIN V6  [get_ports dac_wr1_n]
set_property PACKAGE_PIN R6  [get_ports dac_wr2_n]
set_property PACKAGE_PIN V7  [get_ports dac_xfer_n]

set_property IOSTANDARD LVCMOS33 [get_ports {dac_d[*]}]
set_property IOSTANDARD LVCMOS33 [get_ports dac_ile]
set_property IOSTANDARD LVCMOS33 [get_ports dac_cs_n]
set_property IOSTANDARD LVCMOS33 [get_ports dac_wr1_n]
set_property IOSTANDARD LVCMOS33 [get_ports dac_wr2_n]
set_property IOSTANDARD LVCMOS33 [get_ports dac_xfer_n]

#=============================================================================
# XADC Analog Inputs (oscilloscope frontend board -> J5 expansion)
#=============================================================================
# NOTE: VP_0(J10) and VN_0(K9) are dedicated analog pins — Vivado handles
# these automatically. Do NOT constrain adc_p_in / adc_n_in to regular I/O pins.

# XADC Auxiliary Channel 0 — ADC_MUX_OUT (oscilloscope input, J5 pins 13-14)
# In 4053 mode, this single channel carries the time-multiplexed CH1+CH2 signal
# from the 74HC4053D mux output (ADC_MUX_OUT).
# J5 pin 13 = AD0P → FPGA D14 (VAUXP[0] on XC7A35T-CSG324)
# J5 pin 14 = AD0N → FPGA C14 (VAUXN[0]) — tie to GND externally for single-ended
set_property PACKAGE_PIN D14 [get_ports adc_vauxp0]
set_property PACKAGE_PIN C14 [get_ports adc_vauxn0]
set_property IOSTANDARD LVCMOS33 [get_ports adc_vauxp0]
set_property IOSTANDARD LVCMOS33 [get_ports adc_vauxn0]

# XADC Auxiliary Channel 3 (J5 pins 5-6, AD3P/AD3N) — REMOVED
# When USE_4053=1, VAUXP[3]/VAUXN[3] are unused and tied to GND in RTL.
# Ports removed from top.v to avoid XADC shape placement conflicts
# between VAUXP[0] (D14/C14) and VAUXP[3] (A13/A14).
# Package pins A13/A14 = AD3P/AD3N (VAUXP[3]/VAUXN[3]) — available for future use.

#=============================================================================
# 4053 Analog Switch Control (MUX_SEL)
#=============================================================================
# MUX_SEL drives the 74HC4053D S1 select pin on the expansion board.
# 0 = CH1 connected to ADC, 1 = CH2 connected to ADC.
# Connected to EGO1 J5 pin 31 (IO_L18P) → FPGA H17 (IO_L18P_T2_34, bank 34)
set_property PACKAGE_PIN H17 [get_ports mux_sel]
set_property IOSTANDARD LVCMOS33 [get_ports mux_sel]

#=============================================================================
# Buttons (5x) -- EGO1 built-in
#   btn[0] = amplitude up, btn[1] = amplitude down
#   btn[2] = mod depth up, btn[3] = mod depth down
#   btn[4] = scope trigger adjust
#=============================================================================
set_property PACKAGE_PIN R11 [get_ports {btn[0]}]
set_property PACKAGE_PIN R17 [get_ports {btn[1]}]
set_property PACKAGE_PIN R15 [get_ports {btn[2]}]
set_property PACKAGE_PIN V1  [get_ports {btn[3]}]
set_property PACKAGE_PIN U4  [get_ports {btn[4]}]

set_property IOSTANDARD LVCMOS33 [get_ports {btn[*]}]

#=============================================================================
# Slide Switches (8x) -- EGO1 built-in
#   sw_in[1:0] = main mode (00=sig gen, 01=scope, 10=lissajous, 11=kaleidoscope)
#   sw_in[4:2] = sub-mode / wave type
#   sw_in[7:5] = frequency coarse range
#=============================================================================
set_property PACKAGE_PIN R1  [get_ports {sw_in[0]}]
set_property PACKAGE_PIN N4  [get_ports {sw_in[1]}]
set_property PACKAGE_PIN M4  [get_ports {sw_in[2]}]
set_property PACKAGE_PIN R2  [get_ports {sw_in[3]}]
set_property PACKAGE_PIN P2  [get_ports {sw_in[4]}]
set_property PACKAGE_PIN P3  [get_ports {sw_in[5]}]
set_property PACKAGE_PIN P4  [get_ports {sw_in[6]}]
set_property PACKAGE_PIN P5  [get_ports {sw_in[7]}]

set_property IOSTANDARD LVCMOS33 [get_ports {sw_in[*]}]

#=============================================================================
# DIP Switches (8x) -- EGO1 built-in
#   sw_dip[7:0] = frequency fine (0-255 * 20Hz steps)
#=============================================================================
set_property PACKAGE_PIN T5  [get_ports {sw_dip[0]}]
set_property PACKAGE_PIN T3  [get_ports {sw_dip[1]}]
set_property PACKAGE_PIN R3  [get_ports {sw_dip[2]}]
set_property PACKAGE_PIN V4  [get_ports {sw_dip[3]}]
set_property PACKAGE_PIN V5  [get_ports {sw_dip[4]}]
set_property PACKAGE_PIN V2  [get_ports {sw_dip[5]}]
set_property PACKAGE_PIN U2  [get_ports {sw_dip[6]}]
set_property PACKAGE_PIN U3  [get_ports {sw_dip[7]}]

set_property IOSTANDARD LVCMOS33 [get_ports {sw_dip[*]}]

#=============================================================================
# Status LEDs (3x) -- EGO1 built-in
#   led_speed[0] = sig gen mode
#   led_speed[1] = scope mode
#   led_speed[2] = lissajous/kaleidoscope mode
#=============================================================================
set_property PACKAGE_PIN K3  [get_ports {led_speed[0]}]
set_property PACKAGE_PIN M1  [get_ports {led_speed[1]}]
set_property PACKAGE_PIN L1  [get_ports {led_speed[2]}]

set_property IOSTANDARD LVCMOS33 [get_ports {led_speed[*]}]

#=============================================================================
# Loopback Test Pins (Tx -> Rx for self-test)
#   NOTE: loop_rx[1] reassigned from C14 to F13 because C14 is now AD0N
#         (VAUXN[0], J5 pin 14). For loopback test, use external jumpers to
#         connect any loop_tx to any available input pin.
#=============================================================================
set_property PACKAGE_PIN H16 [get_ports {loop_tx[0]}]
set_property PACKAGE_PIN G16 [get_ports {loop_tx[1]}]
set_property PACKAGE_PIN F15 [get_ports {loop_tx[2]}]
set_property PACKAGE_PIN F16 [get_ports {loop_tx[3]}]
set_property IOSTANDARD LVCMOS33 [get_ports {loop_tx[*]}]

set_property PACKAGE_PIN A15 [get_ports {loop_rx[0]}]
set_property PACKAGE_PIN F13 [get_ports {loop_rx[1]}]
set_property PACKAGE_PIN B18 [get_ports {loop_rx[2]}]
set_property PACKAGE_PIN B13 [get_ports {loop_rx[3]}]
set_property IOSTANDARD LVCMOS33 [get_ports {loop_rx[*]}]

#=============================================================================
# Debug Ports (optional, for logic analyzer monitoring)
#=============================================================================
# Uncomment to assign debug pins:
# set_property PACKAGE_PIN xx [get_ports {dbg_dds_out[0]}]
# ...
