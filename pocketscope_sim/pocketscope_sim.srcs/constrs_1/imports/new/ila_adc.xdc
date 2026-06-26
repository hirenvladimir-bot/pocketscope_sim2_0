#=============================================================================
# ILA ADC Debug Constraints
#=============================================================================
# Clock constraint for the ILA debug hub (JTAG clock — free-running).
# The ILA probe port is clocked by sys_clk (100MHz), which is already
# constrained in pocketscope.xdc.
#
# The dbg_hub clock (JTAG TCK) does not need a user constraint — Vivado
# derives it automatically from the hardware target frequency.
#=============================================================================

# ILA probe clock is sys_clk — already constrained in pocketscope.xdc:
#   create_clock -period 10.000 -name sys_clk_pin [get_ports sys_clk]
#
# No additional clock constraints needed. The ILA core's .clk port connects
# directly to sys_clk.
