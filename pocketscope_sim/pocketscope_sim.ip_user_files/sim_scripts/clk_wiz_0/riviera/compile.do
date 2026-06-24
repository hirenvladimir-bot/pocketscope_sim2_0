transcript off
onbreak {quit -force}
onerror {quit -force}
transcript on

vlib work
vlib riviera/xpm
vlib riviera/xil_defaultlib

vmap xpm riviera/xpm
vmap xil_defaultlib riviera/xil_defaultlib

vlog -work xpm  -incr "+incdir+../../../ipstatic" "+incdir+../../../../../../FPGA/2025.1/Vivado/data/rsb/busdef" -l xpm -l xil_defaultlib \
"D:/FPGA/2025.1/Vivado/data/ip/xpm/xpm_cdc/hdl/xpm_cdc.sv" \

vcom -work xpm -93  -incr \
"D:/FPGA/2025.1/Vivado/data/ip/xpm/xpm_VCOMP.vhd" \

vcom -work xil_defaultlib -93  -incr \
"../../../../pocketscope_sim.gen/sources_1/ip/clk_wiz_0/proc_common_v3_00_a/hdl/src/vhdl/clk_wiz_0_conv_funs_pkg.vhd" \
"../../../../pocketscope_sim.gen/sources_1/ip/clk_wiz_0/proc_common_v3_00_a/hdl/src/vhdl/clk_wiz_0_proc_common_pkg.vhd" \
"../../../../pocketscope_sim.gen/sources_1/ip/clk_wiz_0/proc_common_v3_00_a/hdl/src/vhdl/clk_wiz_0_ipif_pkg.vhd" \
"../../../../pocketscope_sim.gen/sources_1/ip/clk_wiz_0/clk_wiz_0_clk_mon.vhd" \
"../../../../pocketscope_sim.gen/sources_1/ip/clk_wiz_0/proc_common_v3_00_a/hdl/src/vhdl/clk_wiz_0_family_support.vhd" \
"../../../../pocketscope_sim.gen/sources_1/ip/clk_wiz_0/proc_common_v3_00_a/hdl/src/vhdl/clk_wiz_0_family.vhd" \
"../../../../pocketscope_sim.gen/sources_1/ip/clk_wiz_0/proc_common_v3_00_a/hdl/src/vhdl/clk_wiz_0_soft_reset.vhd" \
"../../../../pocketscope_sim.gen/sources_1/ip/clk_wiz_0/proc_common_v3_00_a/hdl/src/vhdl/clk_wiz_0_pselect_f.vhd" \
"../../../../pocketscope_sim.gen/sources_1/ip/clk_wiz_0/axi_lite_ipif_v1_01_a/hdl/src/vhdl/clk_wiz_0_address_decoder.vhd" \
"../../../../pocketscope_sim.gen/sources_1/ip/clk_wiz_0/axi_lite_ipif_v1_01_a/hdl/src/vhdl/clk_wiz_0_slave_attachment.vhd" \
"../../../../pocketscope_sim.gen/sources_1/ip/clk_wiz_0/axi_lite_ipif_v1_01_a/hdl/src/vhdl/clk_wiz_0_axi_lite_ipif.vhd" \
"../../../../pocketscope_sim.gen/sources_1/ip/clk_wiz_0/clk_wiz_0_clk_wiz_drp.vhd" \
"../../../../pocketscope_sim.gen/sources_1/ip/clk_wiz_0/clk_wiz_0_axi_clk_config.vhd" \

vlog -work xil_defaultlib  -incr -v2k5 "+incdir+../../../ipstatic" "+incdir+../../../../../../FPGA/2025.1/Vivado/data/rsb/busdef" -l xpm -l xil_defaultlib \
"../../../../pocketscope_sim.gen/sources_1/ip/clk_wiz_0/clk_wiz_0_clk_wiz.v" \
"../../../../pocketscope_sim.gen/sources_1/ip/clk_wiz_0/clk_wiz_0.v" \

vlog -work xil_defaultlib \
"glbl.v"

