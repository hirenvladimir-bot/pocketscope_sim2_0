#=============================================================================
# create_ila_adc.tcl — Create ILA IP core for XADC debug monitoring
#=============================================================================
# Usage:
#   GUI: Open project, then Tcl Console:  source create_ila_adc.tcl
#   Batch: vivado -mode batch -source create_ila_adc.tcl
#
# Creates ILA IP "ila_adc": 100MHz, 1 probe x 64 bits, depth 2048
#=============================================================================

# ---- Auto-open project if running in batch mode ----
if {[current_project -quiet] eq ""} {
    set proj_path "C:/Users/sgzmd/Desktop/pocketscope_sim2_0/pocketscope_sim/pocketscope_sim.xpr"
    if {[file exists $proj_path]} {
        puts "Opening project: $proj_path"
        open_project $proj_path
    } else {
        puts "ERROR: Project not found at $proj_path"
        return
    }
}

set ip_name "ila_adc"
set proj_dir [get_property DIRECTORY [current_project]]
set ip_dir  "$proj_dir/pocketscope_sim.srcs/sources_1/ip"

# ---- Cleanup: remove stale ila_test if left over from diagnostics ----
set test_ips [get_ips -quiet -all -filter {NAME =~ "*ila_test*"}]
if {[llength $test_ips] > 0} {
    puts "Cleaning up leftover test IPs..."
    foreach tip $test_ips {
        catch {remove_files [get_files -of_objects $tip]}
    }
}

# ---- Check if IP already exists ----
if {[get_ips -quiet $ip_name] ne ""} {
    puts "IP '$ip_name' already exists. Updating configuration..."
} else {
    puts "Creating ILA IP: $ip_name ..."
    # Don't specify version — Vivado picks latest available
    create_ip \
        -name ila \
        -vendor xilinx.com \
        -library ip \
        -module_name $ip_name \
        -dir $ip_dir
}

# ---- Configure ILA ----
set_property -dict [list \
    CONFIG.C_COMPONENT_NAME            "$ip_name" \
    CONFIG.C_NUM_OF_PROBES             1 \
    CONFIG.C_PROBE0_WIDTH              64 \
    CONFIG.C_DATA_DEPTH                2048 \
    CONFIG.C_EN_STRG_QUAL              1 \
    CONFIG.C_ADV_TRIGGER               1 \
    CONFIG.C_INPUT_PIPE_STAGES         2 \
    CONFIG.C_TRIGIN_EN                 0 \
    CONFIG.C_TRIGOUT_EN                0 \
] [get_ips $ip_name]

puts "ILA '${ip_name}' configured: 1 probe x 64 bits, depth 2048"

# ---- Generate output products ----
puts "Generating output products..."
generate_target {instantiation_template} [get_ips $ip_name]
generate_target all [get_ips $ip_name]

# ---- Add ila_adc_debug.v and ila_adc.xdc to project if not already added ----
# Check and add the ila_adc_debug.v source
set debug_v "$proj_dir/pocketscope_sim.srcs/sources_1/new/ila_adc_debug.v"
set already_v [get_files -quiet -filter {NAME =~ "*ila_adc_debug*"}]
if {[llength $already_v] == 0} {
    puts "Adding ila_adc_debug.v to project..."
    import_files -fileset sources_1 $debug_v
} else {
    puts "ila_adc_debug.v already in project."
}

# Check and add the ila_adc.xdc constraint
set debug_xdc "$proj_dir/pocketscope_sim.srcs/constrs_1/new/ila_adc.xdc"
set already_x [get_files -quiet -filter {NAME =~ "*ila_adc*"}]
if {[llength $already_x] == 0} {
    puts "Adding ila_adc.xdc to project..."
    import_files -fileset constrs_1 $debug_xdc
} else {
    puts "ila_adc.xdc already in project."
}

# Reorder compile
update_compile_order -fileset sources_1

puts ""
puts "============================================"
puts "  ILA '${ip_name}' SETUP COMPLETE"
puts "============================================"
puts ""
puts "Next steps (in Vivado GUI):"
puts "  1. Run Synthesis"
puts "  2. Run Implementation"
puts "  3. Generate Bitstream"
puts "  4. Program device -> Open Hardware Manager -> ILA"

close_project
