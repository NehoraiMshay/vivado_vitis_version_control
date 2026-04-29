# File: run_vitis_export.tcl

# Detect where THIS script is located to find the python tool
set script_path [file dirname [file normalize [info script]]]
set python_tool "$script_path/vitis_automation.py"

puts "================================================================"
puts "🚀 EXECUTION STARTED: run_vitis_export.tcl"
puts "================================================================"

# Retrieve the current workspace path directly from XSCT
set ws_path [getws]

if {$ws_path eq ""} {
    puts "❌ ERROR: No active Vitis workspace found. Please set it using 'setws <path>'."
    return
}

puts "⚙️  Active Workspace: $ws_path"
puts "⚙️  Running Vitis Automation (Repo Copy & Zip)..."

# Save and Unset Conflicting Environment Variables
set env_vars_to_clear {PYTHONPATH PYTHONHOME TCL_LIBRARY TK_LIBRARY}
set saved_env_vars [dict create]

foreach var $env_vars_to_clear {
    if {[info exists ::env($var)]} {
        dict set saved_env_vars $var $::env($var)
        unset ::env($var)
    }
}

# Execute Python, passing the workspace path as an argument
if {[catch {exec python $python_tool $ws_path} result]} {
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
puts "🎉 VITIS EXPORT DONE."
puts "================================================================"