#=============================================================================
# fix_ila.tcl — 修复 ILA ADC Debug 综合错误
# 在 Vivado Tcl Console 中运行: source fix_ila.tcl
#=============================================================================

puts "========================================"
puts " Fixing ILA ADC Debug — adding missing files"
puts "========================================"

# 1. 添加 ILA debug wrapper 源文件
puts ">>> Adding ila_adc_debug.v to sources_1..."
add_files -fileset sources_1 -norecurse \
    C:/Users/sgzmd/Desktop/pocketscope_sim2_0/pocketscope_sim/pocketscope_sim.srcs/sources_1/new/ila_adc_debug.v

# 2. 添加 ILA IP core
puts ">>> Adding ila_adc IP to project..."
add_files -fileset sources_1 -norecurse \
    C:/Users/sgzmd/Desktop/pocketscope_sim2_0/pocketscope_sim/pocketscope_sim.srcs/sources_1/ip/ila_adc_1/ila_adc.xci

# 3. 生成 IP output products (synthesis)
puts ">>> Generating IP output products..."
generate_target {synthesis} [get_ips ila_adc]

# 4. 更新编译顺序
puts ">>> Updating compile order..."
update_compile_order -fileset sources_1

# 5. 重置并重新启动综合+实现
puts ">>> Resetting synthesis and launching bitstream generation..."
reset_run synth_1
launch_runs impl_1 -to_step write_bitstream -jobs 16

puts "========================================"
puts " Done. Check run progress in the Design Runs tab."
puts "========================================"
