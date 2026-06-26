#=============================================================================
# run_full_flow.tcl — ILA creation + Synthesis + Implementation + Bitstream
#=============================================================================
# Usage: vivado -mode batch -source run_full_flow.tcl
#=============================================================================

set proj_path "C:/Users/sgzmd/Desktop/pocketscope_sim2_0/pocketscope_sim/pocketscope_sim.xpr"
set proj_dir  "C:/Users/sgzmd/Desktop/pocketscope_sim2_0/pocketscope_sim"
set ip_name   "ila_adc"
set ip_dir    "$proj_dir/pocketscope_sim.srcs/sources_1/ip"

#=============================================================================
# Phase 1: Open Project & Create ILA IP
#=============================================================================
puts "\n========== PHASE 1: Project Setup & ILA Creation =========="

if {[catch {open_project $proj_path} err]} {
    puts "ERROR opening project: $err"
    exit 1
}

# Import required source files if not already present
set debug_v "$proj_dir/pocketscope_sim.srcs/sources_1/new/ila_adc_debug.v"
set debug_xdc "$proj_dir/pocketscope_sim.srcs/constrs_1/new/ila_adc.xdc"

if {[llength [get_files -quiet $debug_v]] == 0} {
    puts "Adding ila_adc_debug.v to project..."
    import_files -fileset sources_1 $debug_v
}
if {[llength [get_files -quiet $debug_xdc]] == 0} {
    puts "Adding ila_adc.xdc to project..."
    import_files -fileset constrs_1 $debug_xdc
}

# Create ILA IP
set ip_already [get_ips -quiet $ip_name]
if {$ip_already ne ""} {
    puts "ILA '$ip_name' exists. Upgrading if needed..."
    upgrade_ip [get_ips $ip_name] -quiet
} else {
    puts "Creating ILA IP: $ip_name ..."
    create_ip -name ila -vendor xilinx.com -library ip -module_name $ip_name -dir $ip_dir
}

# Configure ILA with safe defaults
puts "Configuring ILA..."
set ip_obj [get_ips $ip_name]

# Core sizing
set_property CONFIG.C_NUM_OF_PROBES 1 $ip_obj
set_property CONFIG.C_PROBE0_WIDTH  64 $ip_obj
set_property CONFIG.C_DATA_DEPTH    2048 $ip_obj

# Trigger features (try each — some may not exist in this Vivado version)
foreach {prop val} {
    CONFIG.C_EN_STRG_QUAL         1
    CONFIG.C_ADV_TRIGGER          1
    CONFIG.C_INPUT_PIPE_STAGES    2
    CONFIG.C_TRIGIN_EN            0
    CONFIG.C_TRIGOUT_EN           0
} {
    catch {set_property $prop $val $ip_obj}
}

puts "Generating ILA output products..."
generate_target all $ip_obj

update_compile_order -fileset sources_1

puts "ILA IP setup complete."

#=============================================================================
# Phase 2: Synthesis
#=============================================================================
puts "\n========== PHASE 2: Synthesis =========="

reset_run synth_1
launch_runs synth_1 -jobs 16
wait_on_run synth_1

set synth_status [get_property STATUS [get_runs synth_1]]
puts "Synthesis status: $synth_status"
if {[string match "*Complete*" $synth_status] == 0} {
    puts "ERROR: Synthesis did not complete successfully."
    puts "Check the log file for details."
    close_project
    exit 1
}

#=============================================================================
# Phase 3: Implementation
#=============================================================================
puts "\n========== PHASE 3: Implementation =========="

reset_run impl_1
launch_runs impl_1 -jobs 16
wait_on_run impl_1

set impl_status [get_property STATUS [get_runs impl_1]]
puts "Implementation status: $impl_status"
if {[string match "*Complete*" $impl_status] == 0} {
    puts "ERROR: Implementation did not complete successfully."
    close_project
    exit 1
}

#=============================================================================
# Phase 4: Bitstream
#=============================================================================
puts "\n========== PHASE 4: Bitstream Generation =========="

launch_runs impl_1 -to_step write_bitstream -jobs 16
wait_on_run impl_1

set bs_status [get_property STATUS [get_runs impl_1]]
puts "Bitstream status: $bs_status"
if {[string match "*Complete*" $bs_status] == 0} {
    puts "ERROR: Bitstream generation did not complete successfully."
    close_project
    exit 1
}

set bit_file "[get_property DIRECTORY [get_runs impl_1]]/top.bit"
puts "\n============================================"
puts "  FULL FLOW COMPLETED SUCCESSFULLY"
puts "  Bitstream: $bit_file"
puts "============================================"

close_project
