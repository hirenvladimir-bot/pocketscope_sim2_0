#=============================================================================
# setup_ila_flow.tcl — Full flow: create ILA IP, add files, run synth+impl+bitstream
# Usage: vivado -mode batch -source setup_ila_flow.tcl
#=============================================================================

# Open the project
set proj_path "C:/Users/sgzmd/Desktop/pocketscope_sim2_0/pocketscope_sim/pocketscope_sim.xpr"
puts "Opening project: $proj_path"
open_project $proj_path

# ---- Step 1: Create ILA IP if it doesn't exist ----
set ip_name "ila_adc"
if {[get_ips -quiet $ip_name] ne ""} {
    puts "ILA IP '$ip_name' already exists. Skipping creation."
} else {
    puts "Creating ILA IP: $ip_name ..."

    # Auto-detect available ILA version
    set ila_versions [get_ipdefs -all -filter {NAME == "ila"}]
    if {[llength $ila_versions] == 0} {
        puts "ERROR: No ILA IP definition found. Check Vivado installation."
        close_project
        exit 1
    }

    # Use the latest available version
    set latest_ver [lindex [lsort -decreasing $ila_versions] 0]
    puts "Using ILA version: $latest_ver"

    create_ip \
        -name ila \
        -vendor xilinx.com \
        -library ip \
        -version $latest_ver \
        -module_name $ip_name \
        -dir "[get_property DIRECTORY [current_project]]/pocketscope_sim.srcs/sources_1/ip"

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

    puts "Generating ILA output products..."
    generate_target {instantiation_template} [get_ips $ip_name]
    generate_target all [get_ips $ip_name]

    puts "ILA '$ip_name' created successfully."
}

# ---- Step 2: Ensure ila_adc_debug.v and ila_adc.xdc are in the project ----
# The .xpr file has already been updated with these files.
# Vivado will pick them up when it opens the project.
# Just do a refresh
puts "Updating compile order..."
update_compile_order -fileset sources_1
update_compile_order -fileset constrs_1

# ---- Step 3: Run Synthesis ----
puts "\n====== Running Synthesis ======"
reset_run synth_1
launch_runs synth_1 -jobs 16
wait_on_run synth_1

# Check for errors
set synth_status [get_property STATUS [get_runs synth_1]]
if {$synth_status ne "synth_design Complete!"} {
    puts "ERROR: Synthesis failed with status: $synth_status"
    set synth_log [get_property LOG_FILE [get_runs synth_1]]
    puts "Check log: $synth_log"
    close_project
    exit 1
}
puts "Synthesis completed successfully."

# ---- Step 4: Run Implementation ----
puts "\n====== Running Implementation ======"
reset_run impl_1
launch_runs impl_1 -jobs 16
wait_on_run impl_1

set impl_status [get_property STATUS [get_runs impl_1]]
if {$impl_status ne "route_design Complete!"} {
    puts "ERROR: Implementation failed with status: $impl_status"
    close_project
    exit 1
}
puts "Implementation completed successfully."

# ---- Step 5: Generate Bitstream ----
puts "\n====== Generating Bitstream ======"
launch_runs impl_1 -to_step write_bitstream -jobs 16
wait_on_run impl_1

set bs_status [get_property STATUS [get_runs impl_1]]
if {$bs_status ne "write_bitstream Complete!"} {
    puts "ERROR: Bitstream generation failed with status: $bs_status"
    close_project
    exit 1
}

puts "\n====== FULL FLOW COMPLETED SUCCESSFULLY ======"
puts "Bitstream: [get_property DIRECTORY [current_run]]/top.bit"

close_project
