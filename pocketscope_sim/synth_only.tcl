# Minimal synthesis script
set proj_path "C:/Users/sgzmd/Desktop/pocketscope_sim2_0/pocketscope_sim/pocketscope_sim.xpr"
open_project $proj_path

# Reset and launch synthesis
reset_run synth_1
puts "Launching synthesis..."
launch_runs synth_1 -jobs 16
wait_on_run synth_1

set st [get_property STATUS [get_runs synth_1]]
puts "Synthesis status: $st"

if {[string match "*ERROR*" $st] || [string match "*failed*" $st]} {
    puts "SYNTHESIS FAILED"
    # Print last 30 lines of run log
    set logf [get_property LOG_FILE [get_runs synth_1]]
    puts "Last errors from $logf :"
    set fh [open $logf r]
    set lines [split [read $fh] "\n"]
    close $fh
    set start [expr {[llength $lines] - 40}]
    if {$start < 0} { set start 0 }
    foreach line [lrange $lines $start end] {
        if {[string match "*ERROR*" $line] || [string match "*Warning*" $line] || [string match "*error*" $line]} {
            puts $line
        }
    }
} else {
    puts "SYNTHESIS SUCCESS"
}

close_project
