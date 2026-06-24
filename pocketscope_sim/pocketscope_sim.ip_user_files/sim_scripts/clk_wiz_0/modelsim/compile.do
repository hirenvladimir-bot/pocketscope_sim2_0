vlib modelsim_lib/work
vlib modelsim_lib/msim

vlib modelsim_lib/msim/xpm
vlib modelsim_lib/msim/xil_defaultlib

vmap xpm modelsim_lib/msim/xpm
vmap xil_defaultlib modelsim_lib/msim/xil_defaultlib

vlog -work xpm  -incr -mfcu  -sv "+incdir+../../../ipstatic" "+incdir+../../../../../../FPGA/2025.1/Vivado/data/rsb/busdef" \
"D:/FPGA/2025.1/Vivado/data/ip/xpm/xpm_cdc/hdl/xpm_cdc.sv" \

vcom -work xpm  -93  \
"D:/FPGA/2025.1/Vivado/data/ip/xpm/xpm_VCOMP.vhd" \

vcom -work xil_defaultlib  -93  \
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

vlog -work xil_defaultlib  -incr -mfcu  "+incdir+../../../ipstatic" "+incdir+../../../../../../FPGA/2025.1/Vivado/data/rsb/busdef" \
"../../../../pocketscope_sim.gen/sources_1/ip/clk_wiz_0/clk_wiz_0_clk_wiz.v" \
"../../../../pocketscope_sim.gen/sources_1/ip/clk_wiz_0/clk_wiz_0.v" \

vlog -work xil_defaultlib \
"glbl.v"

