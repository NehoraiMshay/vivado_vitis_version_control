# --- Helper for Recursive File Search ---
proc recursive_glob {dir pattern} {
    set files [glob -nocomplain -directory $dir -- $pattern]
    foreach subdir [glob -nocomplain -type d -directory $dir -- *] {
        set files [concat $files [recursive_glob $subdir $pattern]]
    }
    return $files
}

# --- Helper for Recursive Directory Search ---
proc recursive_dir_glob {dir pattern} {
    set matched_dirs [glob -nocomplain -type d -directory $dir -- $pattern]
    foreach subdir [glob -nocomplain -type d -directory $dir -- *] {
        set matched_dirs [concat $matched_dirs [recursive_dir_glob $subdir $pattern]]
    }
    return $matched_dirs
}

# --- Configuration ---
set zip_list [glob -nocomplain "*_export.zip"]

if {[llength $zip_list] == 0} {
    error "Could not find any file matching *_export.zip in the current directory."
}

set zip_name [lindex $zip_list 0]
if {[llength $zip_list] > 1} {
    puts "Warning: Multiple *_export.zip files found. Defaulting to: $zip_name"
}

set extract_dir [file normalize [file rootname $zip_name]]

# 1. Strip the .zip extension (e.g., "my_project_export.zip" -> "my_project_export")
set base_name [file rootname $zip_name]

# 2. Strip "_export" from the end of the string (-> "my_project")
regsub {_export$} $base_name "" clean_name

# 3. Set the workspace directory to use this new cleaned name
set workspace_dir "[pwd]/$clean_name"

# 1. Setup Folders
file mkdir $extract_dir

if {[file exists $workspace_dir]} { 
    error "The workspace directory already exists: $workspace_dir"
} else {
    file mkdir $workspace_dir 
}

# 2. Extract Zip
puts "Extracting $zip_name into $extract_dir..."
if {[catch {exec powershell -command "Expand-Archive -Path '$zip_name' -DestinationPath '$extract_dir' -Force"} msg]} {
    error "Extraction failed: $msg"
}

# 3. Locate and Move XSA
set xsa_list [recursive_glob $extract_dir "*.xsa"]
if {[llength $xsa_list] == 0} { error "Could not find an XSA file in the extracted archive." }
set source_xsa [lindex $xsa_list 0]
set xsa_filename [file tail $source_xsa]
set local_xsa_path [file join $workspace_dir $xsa_filename]

puts "Moving $xsa_filename to local workspace..."
file copy -force $source_xsa $local_xsa_path

# 4. Locate and Move Automation Scripts
puts "Locating automation scripts..."
set py_files [recursive_glob $extract_dir "vitis_automation.py"]
if {[llength $py_files] > 0} {
    file copy -force [lindex $py_files 0] [file join $workspace_dir "vitis_automation.py"]
}

set tcl_export_files [recursive_glob $extract_dir "run_vitis_export.tcl"]
if {[llength $tcl_export_files] > 0} {
    file copy -force [lindex $tcl_export_files 0] [file join $workspace_dir "run_vitis_export.tcl"]
}

# 5. Locate and Parse platform.spr
set spr_list [recursive_glob $extract_dir "platform.spr"]
if {[llength $spr_list] == 0} { error "Could not find platform.spr" }
set spr_file [lindex $spr_list 0]

puts "Parsing $spr_file..."
set fp [open $spr_file r]
set spr_content [read $fp]
close $fp

regexp {"platformName"\s*:\s*"([^"]+)"} $spr_content -> platform_name
if {![info exists platform_name]} { set platform_name "custom_platform" }

# Determine if the original platform used -no-boot-bsp
set plat_is_no_boot_bsp "false"
if {[regexp {"platIsNoBootBsp"\s*:\s*"([^"]+)"} $spr_content match no_boot_str]} {
    set plat_is_no_boot_bsp $no_boot_str
} elseif {[regexp {"platIsNoBootBsp"\s*:\s*(true|false)} $spr_content match no_boot_bool]} {
    set plat_is_no_boot_bsp $no_boot_bool
}

# Extract Domain Information
set mapped_content [string map [list "\"domainName\":" "\x01"] $spr_content]
set domain_chunks [split $mapped_content "\x01"]
set domains_list {}

for {set i 1} {$i < [llength $domain_chunks]} {incr i} {
    set chunk [lindex $domain_chunks $i]
    
    regexp {^\s*"([^"]+)"} $chunk -> d_name
    regexp {"domainDispName"\s*:\s*"([^"]+)"} $chunk -> d_disp
    regexp {"os"\s*:\s*"([^"]+)"} $chunk -> d_os
    regexp {"processors"\s*:\s*"([^"]+)"} $chunk -> d_proc
    regexp {"arch"\s*:\s*"([^"]+)"} $chunk -> d_arch
    regexp {"domType"\s*:\s*"([^"]+)"} $chunk -> d_type
    regexp {"compatibleApp"\s*:\s*"([^"]*)"} $chunk -> d_comp_app

    if {[info exists d_name] && [info exists d_os] && [info exists d_proc]} {
        if {![info exists d_arch]} { set d_arch "" }
        if {![info exists d_disp]} { set d_disp $d_name }
        if {![info exists d_type]} { set d_type "mssDomain" }
        if {![info exists d_comp_app]} { set d_comp_app "" }
        
        # CLEANUP: Strip any invisible whitespace/newlines
        set d_name [string trim $d_name]
        
        lappend domains_list [list $d_name $d_disp $d_os $d_proc $d_arch $d_type $d_comp_app]
    }
    catch {unset d_name d_disp d_os d_proc d_arch d_type d_comp_app}
}

if {[llength $domains_list] == 0} {
    error "CRITICAL: No domains were parsed from platform.spr."
}

# 6. Initialize Workspace & Create Platform
setws $workspace_dir
puts "Creating platform '$platform_name'..."

if {$plat_is_no_boot_bsp == "true"} {
    set plat_cmd "platform create -name {$platform_name} -hw {$local_xsa_path} -no-boot-bsp"
    puts "  -> Original platform had no boot BSPs. Enforcing -no-boot-bsp."
    eval $plat_cmd
} else {
    # Extract explicit fsbl target processor from SPR
    set fsbl_target ""
    regexp {"platFsblTarget"\s*:\s*"([^"]+)"} $spr_content -> fsbl_target
    
    # Dynamically match the FSBL processor to its architecture from the domains list
    set fsbl_arch "64-bit" ;# Fallback
    foreach dom $domains_list {
        lassign $dom d_name d_disp d_os d_proc d_arch d_type d_comp_app
        # Look specifically for the bootDomain assigned to the FSBL processor
        if {$d_type == "bootDomain" && $d_proc == $fsbl_target} {
            if {$d_arch != ""} { 
                set fsbl_arch $d_arch 
                puts "  -> Discovered bootDomain architecture from SPR: $fsbl_arch"
            }
        }
    }

    if {$fsbl_target != ""} {
        puts "  -> Original platform auto-generated boot BSPs. Forcing FSBL to $fsbl_arch."
        set plat_cmd "platform create -name {$platform_name} -hw {$local_xsa_path} -os standalone -proc {$fsbl_target} -arch {$fsbl_arch} -fsbl-target {$fsbl_target}"
        eval $plat_cmd
        
        # Vitis creates a dummy application domain when OS/Proc are specified. Clean it up.
        puts "  -> Removing dummy default application domain..."
        catch { domain active "standalone_${fsbl_target}"; domain remove }
        catch { domain active "standalone_domain"; domain remove }
    } else {
        set plat_cmd "platform create -name {$platform_name} -hw {$local_xsa_path}"
        eval $plat_cmd
    }
}


# 7. Generate Domains with Defaults (Applying Support Apps)
foreach dom $domains_list {
    lassign $dom d_name d_disp d_os d_proc d_arch d_type d_comp_app

    # If the domain is a boot component and we allowed auto-generation, skip manual creation
    if {$d_type == "bootDomain" && $plat_is_no_boot_bsp == "false"} {
        puts "\nSkipping manual creation of auto-generated boot domain: $d_name"
        continue
    }

    set cmd "domain create -name {$d_name} -display-name {$d_disp} -os {$d_os} -proc {$d_proc}"
    if {$d_arch != ""} {
        append cmd " -arch {$d_arch}"
    }
    if {$d_comp_app != ""} {
        append cmd " -support-app {$d_comp_app}"
    }

    puts "\nCreating Domain: $cmd"
    eval $cmd
}

# 8. Setup Imported Local Repositories
set repo_dir [file join $extract_dir "imported_local_repos"]
if {[file exists $repo_dir] && [file isdirectory $repo_dir]} {
    puts "\n--- Importing Local Repositories ---"
    set repo_subfolders [glob -nocomplain -type d -directory $repo_dir *]
    
    set active_repos {}
    foreach sub $repo_subfolders {
        set repo_name [file tail $sub]
        set dest_repo [file join $workspace_dir $repo_name]
        
        puts "  -> Copying repository '$repo_name' to workspace..."
        file copy -force $sub $dest_repo
        
        set win_path [string map [list "/" "\\\\" "\\" "\\\\"] [file normalize $dest_repo]]
        lappend active_repos $win_path
        
        puts "  -> Queueing repo: $win_path"
    }
    
    if {[llength $active_repos] > 0} {
        set cmd [list repo -set]
        foreach rp $active_repos {
            lappend cmd $rp
        }
        eval $cmd
        puts "  -> Applied all repositories successfully."
    }
}

# 9. Apply MSS Configurations
puts "\n--- Applying MSS Configurations ---"
set all_mss_files [recursive_glob $extract_dir "*.mss"]

foreach dom $domains_list {
    lassign $dom d_name d_disp d_os d_proc d_arch d_type d_comp_app

    # Skip MSS injection for boot domains, leaving them exactly as Vitis generated them
    if {$d_type == "bootDomain"} {
        puts "  -> Skipping MSS application for boot domain: $d_name"
        continue
    }

    set mss_injected 0
    foreach mss_file $all_mss_files {
        set mss_dir [file dirname $mss_file]
        set path_parts [file split $mss_dir]
        
        set valid_folder 0
        foreach folder $path_parts {
            if {[string match -nocase "*$d_name*" $folder]} {
                set valid_folder 1
                break
            }
        }
        
        if {$valid_folder} {
            set source_mss [file normalize $mss_file]
            puts "  -> MATCH FOUND! Applying MSS file from nested folder: $source_mss"
            domain active $d_name
            domain config -mss $source_mss
            set mss_injected 1
            break
        }
    }
    
    if {$mss_injected == 0} {
        puts "  -> ERROR: No .mss file found inside any nested subfolder named after '$d_name'."
    }
}

# 10. Finalize and Generate Platform
puts "\nWriting platform configurations to disk..."
platform write

puts "Generating platform to compile BSPs..."
platform generate

# 11. Copy and Patch System Projects (.sprj)
puts "\n--- Migrating System Projects (.sprj) ---"
set sprj_files [recursive_glob $extract_dir "*.sprj"]
foreach sprj $sprj_files {
    set parent_dir [file dirname $sprj]
    set folder_name [file tail $parent_dir]
    set dest_dir [file join $workspace_dir $folder_name]

    if {![file exists $dest_dir]} {
        puts "  -> Copying System Project '$folder_name'..."
        file copy -force $parent_dir $dest_dir
    }

    set dest_sprj [file join $dest_dir [file tail $sprj]]
    set fp [open $dest_sprj r]
    set content [read $fp]
    close $fp

    if {[regexp {platform="([^"]+)"} $content match old_plat_path]} {
        set xpfm_filename [file tail $old_plat_path]
        set expected_plat_name [file rootname $xpfm_filename]
        
        set new_plat_path [file normalize [file join $workspace_dir $expected_plat_name "export" $expected_plat_name $xpfm_filename]]
        regsub -all "platform=\"$old_plat_path\"" $content "platform=\"$new_plat_path\"" content
        puts "  -> Patched platform path in [file tail $sprj]"
    }

    set fp [open $dest_sprj w]
    puts -nonewline $fp $content
    close $fp
}

# 12. Copy and Patch Application Projects (.prj)
puts "\n--- Migrating Application Projects (.prj) ---"
set prj_files [recursive_glob $extract_dir "*.prj"]
foreach prj $prj_files {
    set parent_dir [file dirname $prj]
    set folder_name [file tail $parent_dir]
    set dest_dir [file join $workspace_dir $folder_name]

    if {![file exists $dest_dir]} {
        puts "  -> Copying Application Project '$folder_name'..."
        file copy -force $parent_dir $dest_dir
    }

    set dest_prj [file join $dest_dir [file tail $prj]]
    set fp [open $dest_prj r]
    set content [read $fp]
    close $fp

    if {[regexp {platform="([^"]+)"} $content match old_plat_path]} {
        set xpfm_filename [file tail $old_plat_path]
        set expected_plat_name [file rootname $xpfm_filename]
        
        set new_plat_path [file normalize [file join $workspace_dir $expected_plat_name "export" $expected_plat_name $xpfm_filename]]
        regsub -all "platform=\"$old_plat_path\"" $content "platform=\"$new_plat_path\"" content
        puts "  -> Patched platform path in [file tail $prj]"
    }

    if {[regexp {location="([^"]+)"} $content match old_loc_path]} {
        set new_loc_path [file normalize $dest_dir]
        regsub -all "location=\"$old_loc_path\"" $content "location=\"$new_loc_path\"" content
        puts "  -> Patched location path in [file tail $prj]"
    }

    set fp [open $dest_prj w]
    puts -nonewline $fp $content
    close $fp
}

# 13. Import to active workspace
puts "\nImporting projects to Vitis Workspace..."
importprojects $workspace_dir

# 14. Disable the Vitis/Eclipse Welcome Screen
puts "\nAttempting to disable the Vitis Welcome Screen..."
set prefs_dir [file join $workspace_dir ".metadata" ".plugins" "org.eclipse.core.runtime" ".settings"]
set prefs_file [file join $prefs_dir "org.eclipse.ui.prefs"]

# ONLY proceed if the directory already exists. Absolutely no folder creation.
if {[file isdirectory $prefs_dir]} {
    set fp [open $prefs_file w]
    puts $fp "eclipse.preferences.version=1"
    puts $fp "showIntro=false"
    close $fp
    puts "Welcome screen disabled."
} else {
    puts "Skipping welcome screen disable: Preferences folder does not exist yet."
}
puts "-------------------------------------------------------"
puts "SUCCESS: Platform, System Projects, and Application Projects rebuilt."
puts "Workspace: $workspace_dir"
puts "-------------------------------------------------------"