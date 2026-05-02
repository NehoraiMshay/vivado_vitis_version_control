# File: run_vivado_export.tcl

# 1. Detect where THIS script is located to find the python tool reliably
set script_path [file dirname [file normalize [info script]]]
set python_tool "$script_path/vivado_automation.py"

set output_tcl_name "Vivado_project_rebuild.tcl"

puts "================================================================"
puts "🚀 EXECUTION STARTED: run_vivado_export.tcl"
puts "================================================================"

# ------------------------------------------------------------------------------
# Step 1: Export Vivado Project
# ------------------------------------------------------------------------------
puts "⚙️  Step 1: Exporting project structure to '$output_tcl_name'..."

# This will use standard Copy Mode (sources are copied into the project).
write_project_tcl -force $output_tcl_name

# ------------------------------------------------------------------------------
# Step 1.2: Extract IP Repository Paths
# ------------------------------------------------------------------------------
puts "⚙️  Step 1.2: Extracting IP Repository paths..."
# Using current_fileset to grab the absolute paths
set ip_repos [get_property IP_REPO_PATHS [current_fileset]]

set ip_file [open "exported_ip_repos.txt" w]
foreach ip_path $ip_repos {
    puts $ip_file $ip_path
}
close $ip_file

# ------------------------------------------------------------------------------
# Step 1.5: Append Cleanup Command to the Generated File
# ------------------------------------------------------------------------------
# This adds the logic to delete 'tcl_imported_src' inside the generated script
puts "⚙️  Step 1.5: Adding auto-cleanup code to '$output_tcl_name'..."

set tcl_file [open $output_tcl_name a]
puts $tcl_file ""
puts $tcl_file "# ------------------------------------------------------------------"
puts $tcl_file "# AUTO-CLEANUP: Delete tcl_imported_src after project creation"
puts $tcl_file "# ------------------------------------------------------------------"
puts $tcl_file "if {\[file exists \"tcl_imported_src\"\]} {"
puts $tcl_file "    puts \"🧹 Cleaning up temporary folder: tcl_imported_src\""
puts $tcl_file "    file delete -force \"tcl_imported_src\""
puts $tcl_file "}"
close $tcl_file

# ------------------------------------------------------------------------------
# Step 2: Run Python Automation (Source Consolidation & Gitignore)
# ------------------------------------------------------------------------------
puts "⚙️  Step 2: Running Project Automation (Consolidation & Gitignore)..."

# Save and Unset Conflicting Environment Variables
set env_vars_to_clear {PYTHONPATH PYTHONHOME TCL_LIBRARY TK_LIBRARY}
set saved_env_vars [dict create]

foreach var $env_vars_to_clear {
    if {[info exists ::env($var)]} {
        dict set saved_env_vars $var $::env($var)
        unset ::env($var)
    }
}

# Execute Python
if {[catch {exec python $python_tool $output_tcl_name} result]} {
    puts "⚠️  PYTHON MESSAGE: $result"
} else {
    puts "✅  PYTHON SUCCESS."
    puts "$result"
}

# Restore Environment Variables
dict for {var val} $saved_env_vars {
    set ::env($var) $val
}

puts "================================================================"
puts "🎉 DONE. Ready to commit."
puts "================================================================"