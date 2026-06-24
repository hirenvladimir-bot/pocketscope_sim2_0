# ============================================================================
# DEPRECATED — SUPERSEDED by pocketscope_sim.srcs/constrs_1/new/pocketscope.xdc
# This file is retained for reference only. Do NOT add it to the active
# constraint set. DAC pins, DIP switches, and button mappings differ from the
# active constraint file.
# ============================================================================
# PocketScope - EGO1 (XC7A35T-1CSG324C) Pin Constraints (OLD VERSION)
# Matches top.v port names
# ============================================================================

# ----------------------------------------------------------------------------
# Clock and Reset
# ----------------------------------------------------------------------------
set_property PACKAGE_PIN P17 [get_ports sys_clk]
set_property IOSTANDARD LVCMOS33 [get_ports sys_clk]

set_property PACKAGE_PIN P15 [get_ports rst_n]
set_property IOSTANDARD LVCMOS33 [get_ports rst_n]

# ----------------------------------------------------------------------------
# ADC Differential Pairs (J5 header)
# ----------------------------------------------------------------------------
set_property PACKAGE_PIN C12 [get_ports adc_p_in]
set_property IOSTANDARD LVCMOS33 [get_ports adc_p_in]

set_property PACKAGE_PIN B12 [get_ports adc_n_in]
set_property IOSTANDARD LVCMOS33 [get_ports adc_n_in]

# ----------------------------------------------------------------------------
# VGA Interface
# ----------------------------------------------------------------------------
set_property PACKAGE_PIN D7 [get_ports hsync]
set_property IOSTANDARD LVCMOS33 [get_ports hsync]

set_property PACKAGE_PIN C4 [get_ports vsync]
set_property IOSTANDARD LVCMOS33 [get_ports vsync]

# Red channel
set_property PACKAGE_PIN B7 [get_ports {vga_r[3]}]
set_property PACKAGE_PIN C5 [get_ports {vga_r[2]}]
set_property PACKAGE_PIN C6 [get_ports {vga_r[1]}]
set_property PACKAGE_PIN F5 [get_ports {vga_r[0]}]
set_property IOSTANDARD LVCMOS33 [get_ports {vga_r[*]}]

# Green channel
set_property PACKAGE_PIN D8 [get_ports {vga_g[3]}]
set_property PACKAGE_PIN A5 [get_ports {vga_g[2]}]
set_property PACKAGE_PIN A6 [get_ports {vga_g[1]}]
set_property PACKAGE_PIN B6 [get_ports {vga_g[0]}]
set_property IOSTANDARD LVCMOS33 [get_ports {vga_g[*]}]

# Blue channel
set_property PACKAGE_PIN E7 [get_ports {vga_b[3]}]
set_property PACKAGE_PIN E5 [get_ports {vga_b[2]}]
set_property PACKAGE_PIN E6 [get_ports {vga_b[1]}]
set_property PACKAGE_PIN C7 [get_ports {vga_b[0]}]
set_property IOSTANDARD LVCMOS33 [get_ports {vga_b[*]}]

# ----------------------------------------------------------------------------
# Input Switches (SW0 - SW7)
# ----------------------------------------------------------------------------
set_property PACKAGE_PIN R1 [get_ports {sw_in[0]}]
set_property IOSTANDARD LVCMOS33 [get_ports {sw_in[0]}]

set_property PACKAGE_PIN N4 [get_ports {sw_in[1]}]
set_property IOSTANDARD LVCMOS33 [get_ports {sw_in[1]}]

set_property PACKAGE_PIN M4 [get_ports {sw_in[2]}]
set_property IOSTANDARD LVCMOS33 [get_ports {sw_in[2]}]

set_property PACKAGE_PIN R2 [get_ports {sw_in[3]}]
set_property IOSTANDARD LVCMOS33 [get_ports {sw_in[3]}]

set_property PACKAGE_PIN P2 [get_ports {sw_in[4]}]
set_property IOSTANDARD LVCMOS33 [get_ports {sw_in[4]}]

set_property PACKAGE_PIN P3 [get_ports {sw_in[5]}]
set_property IOSTANDARD LVCMOS33 [get_ports {sw_in[5]}]

set_property PACKAGE_PIN P4 [get_ports {sw_in[6]}]
set_property IOSTANDARD LVCMOS33 [get_ports {sw_in[6]}]

set_property PACKAGE_PIN P5 [get_ports {sw_in[7]}]
set_property IOSTANDARD LVCMOS33 [get_ports {sw_in[7]}]

# ----------------------------------------------------------------------------
# Push Buttons (PB0, PB1 = btn[0], btn[1])
# ----------------------------------------------------------------------------
set_property PACKAGE_PIN R11 [get_ports {btn[0]}]
set_property IOSTANDARD LVCMOS33 [get_ports {btn[0]}]

set_property PACKAGE_PIN R17 [get_ports {btn[1]}]
set_property IOSTANDARD LVCMOS33 [get_ports {btn[1]}]

# ----------------------------------------------------------------------------
# Status LEDs (LED0 - LED2)
# ----------------------------------------------------------------------------
set_property PACKAGE_PIN K3 [get_ports {led_speed[0]}]
set_property IOSTANDARD LVCMOS33 [get_ports {led_speed[0]}]

set_property PACKAGE_PIN M1 [get_ports {led_speed[1]}]
set_property IOSTANDARD LVCMOS33 [get_ports {led_speed[1]}]

set_property PACKAGE_PIN L1 [get_ports {led_speed[2]}]
set_property IOSTANDARD LVCMOS33 [get_ports {led_speed[2]}]

# ----------------------------------------------------------------------------
# Loopback Test (Tx → Rx)
# ----------------------------------------------------------------------------
set_property PACKAGE_PIN H14 [get_ports {loop_tx[0]}]
set_property PACKAGE_PIN H16 [get_ports {loop_tx[1]}]
set_property PACKAGE_PIN G16 [get_ports {loop_tx[2]}]
set_property PACKAGE_PIN F15 [get_ports {loop_tx[3]}]
set_property PACKAGE_PIN F16 [get_ports {loop_tx[4]}]
set_property IOSTANDARD LVCMOS33 [get_ports {loop_tx[*]}]

set_property PACKAGE_PIN A13 [get_ports {loop_rx[0]}]
set_property PACKAGE_PIN A15 [get_ports {loop_rx[1]}]
set_property PACKAGE_PIN B16 [get_ports {loop_rx[2]}]
set_property PACKAGE_PIN B18 [get_ports {loop_rx[3]}]
set_property PACKAGE_PIN B13 [get_ports {loop_rx[4]}]
set_property IOSTANDARD LVCMOS33 [get_ports {loop_rx[*]}]

# ----------------------------------------------------------------------------
# DAC0832 Interface
# ----------------------------------------------------------------------------
set_property PACKAGE_PIN G3  [get_ports {dac_d[0]}]
set_property PACKAGE_PIN G2  [get_ports {dac_d[1]}]
set_property PACKAGE_PIN H2  [get_ports {dac_d[2]}]
set_property PACKAGE_PIN H1  [get_ports {dac_d[3]}]
set_property PACKAGE_PIN J2  [get_ports {dac_d[4]}]
set_property PACKAGE_PIN J1  [get_ports {dac_d[5]}]
set_property PACKAGE_PIN K2  [get_ports {dac_d[6]}]
set_property PACKAGE_PIN K1  [get_ports {dac_d[7]}]
set_property IOSTANDARD LVCMOS33 [get_ports {dac_d[*]}]

set_property PACKAGE_PIN L2  [get_ports dac_ile]
set_property IOSTANDARD LVCMOS33 [get_ports dac_ile]

set_property PACKAGE_PIN M3  [get_ports dac_cs_n]
set_property IOSTANDARD LVCMOS33 [get_ports dac_cs_n]

set_property PACKAGE_PIN M2  [get_ports dac_wr1_n]
set_property IOSTANDARD LVCMOS33 [get_ports dac_wr1_n]

set_property PACKAGE_PIN N2  [get_ports dac_wr2_n]
set_property IOSTANDARD LVCMOS33 [get_ports dac_wr2_n]

set_property PACKAGE_PIN N1  [get_ports dac_xfer_n]
set_property IOSTANDARD LVCMOS33 [get_ports dac_xfer_n]

# ----------------------------------------------------------------------------
# Unused btn[4:2] pins — tie to ground externally or leave floating
# ----------------------------------------------------------------------------
set_property PACKAGE_PIN T1  [get_ports {btn[2]}]
set_property IOSTANDARD LVCMOS33 [get_ports {btn[2]}]

set_property PACKAGE_PIN T3  [get_ports {btn[3]}]
set_property IOSTANDARD LVCMOS33 [get_ports {btn[3]}]

set_property PACKAGE_PIN U3  [get_ports {btn[4]}]
set_property IOSTANDARD LVCMOS33 [get_ports {btn[4]}]

# ----------------------------------------------------------------------------
# DIP switches (sw_dip[7:0])
# ----------------------------------------------------------------------------
set_property PACKAGE_PIN V5  [get_ports {sw_dip[0]}]
set_property PACKAGE_PIN V4  [get_ports {sw_dip[1]}]
set_property PACKAGE_PIN V3  [get_ports {sw_dip[2]}]
set_property PACKAGE_PIN V2  [get_ports {sw_dip[3]}]
set_property PACKAGE_PIN W5  [get_ports {sw_dip[4]}]
set_property PACKAGE_PIN W4  [get_ports {sw_dip[5]}]
set_property PACKAGE_PIN W3  [get_ports {sw_dip[6]}]
set_property PACKAGE_PIN W2  [get_ports {sw_dip[7]}]
set_property IOSTANDARD LVCMOS33 [get_ports {sw_dip[*]}]
