# Implementation + Bitstream generation
set proj_path "C:/Users/sgzmd/Desktop/pocketscope_sim2_0/pocketscope_sim/pocketscope_sim.xpr"
open_project $proj_path

# Run implementation
puts "\n====== Implementation ======"
reset_run impl_1
launch_runs impl_1 -jobs 16
wait_on_run impl_1

set imp_st [get_property STATUS [get_runs impl_1]]
puts "Implementation status: $imp_st"

if {[string match "*Complete*" $imp_st] == 0} {
    puts "IMPLEMENTATION FAILED"
    # Show errors from impl log
    set logf [get_property LOG_FILE [get_runs impl_1]]
    if {[file exists $logf]} {
        set fh [open $logf r]
        set lines [split [read $fh] "\n"]
        close $fh
        set start [expr {[llength $lines] - 50}]
        if {$start < 0} { set start 0 }
        foreach line [lrange $lines $start end] {
            if {[string match "*ERROR*" $line] || [string match "*FAILED*" $line] || [string match "*Timing*" $line]} {
                puts $line
            }
        }
    }
    close_project
    exit 1
}

# Generate bitstream
puts "\n====== Bitstream ======"
launch_runs impl_1 -to_step write_bitstream -jobs 16
wait_on_run impl_1

set bs_st [get_property STATUS [get_runs impl_1]]
puts "Bitstream status: $bs_st"

if {[string match "*Complete*" $bs_st] == 0} {
    puts "BITSTREAM GENERATION FAILED"
    close_project
    exit 1
}

set bit [glob -nocomplain [get_property DIRECTORY [get_runs impl_1]]/*.bit]
puts "\n============================================"
puts "  FULL FLOW SUCCESSFUL"
puts "  Bitstream: $bit"
puts "============================================"

close_project
