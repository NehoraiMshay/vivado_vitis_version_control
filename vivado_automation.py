import os
import sys
import shutil
import re
from pathlib import Path
import filecmp

# ==============================================================================
# CONFIGURATION
# ==============================================================================
if "TCL_LIBRARY" in os.environ: del os.environ["TCL_LIBRARY"]
if "TK_LIBRARY" in os.environ: del os.environ["TK_LIBRARY"]

SRC_DEST_DIR_NAME = "tcl_imported_src"

# File extensions to look for
EXTS = r"vhd|v|sv|xdc|dcp|xci|bd|tcl|mif|mem|coe"
PATH_PATTERN = re.compile(
    r'"([^"]+\.(?:' + EXTS + r'))"|' 
    r'\{([^\}]+\.(?:' + EXTS + r'))\}|' 
    r'((?:[a-zA-Z]:|[\.\$/\\])[\w\-\./\\\$:{}]+\.(?:' + EXTS + r'))'
, re.IGNORECASE)

# ==============================================================================
# CORE LOGIC
# ==============================================================================
def consolidate_sources(tcl_file_path):
    print("----------------------------------------------------------------")
    print(f"[INFO] Starting Source Consolidation into '{SRC_DEST_DIR_NAME}'...")
    
    tcl_file = Path(tcl_file_path).resolve()
    if not tcl_file.is_file():
        print(f"[ERROR] Tcl file not found: {tcl_file_path}"); return

    # 1. SAFE FRESH START (Backup -> Create New)
    dest_dir = Path.cwd() / SRC_DEST_DIR_NAME
    backup_dir = Path.cwd() / f"_{SRC_DEST_DIR_NAME}_backup"
    
    if backup_dir.exists(): shutil.rmtree(backup_dir, ignore_errors=True)
    
    if dest_dir.exists():
        try: dest_dir.rename(backup_dir)
        except Exception as e:
            print(f"[ERROR] Could not backup existing folder: {e}"); return
    
    dest_dir.mkdir()

    with open(tcl_file, 'r', encoding='utf-8') as f: content = f.read()

    # Mappings
    real_path_map = {}   # Map[Source_Path_Obj] = "final_name.v"
    suffix_lookup = {}   # Map["file.v"] = [Source_Path_Obj_1, ...]
    
    # Inventory of what we have actually put in the new folder (for content check)
    # Map["file.v"] = [Path(dest/file.v), Path(dest/file_2.v)]
    dest_inventory = {}

    def resolve(raw_path):
        clean = raw_path.replace('${origin_dir}', '.').replace('$origin_dir', '.')
        
        # 1. Try Standard Locations
        p = Path(clean)
        if p.exists() and p.is_file(): return p.resolve()
        p2 = Path.cwd() / clean
        if p2.exists() and p2.is_file(): return p2.resolve()

        # 2. Try Backup (Rescue)
        if backup_dir.exists() and SRC_DEST_DIR_NAME in clean.replace('\\', '/'):
            fname = Path(clean).name
            p_bak = backup_dir / fname
            if p_bak.exists() and p_bak.is_file(): return p_bak.resolve()
        
        return None

    # ----------------------------------------------------------------------
    # PASS 1: HARVEST & SMART DEDUPLICATE
    # ----------------------------------------------------------------------
    print("[INFO] Pass 1: Processing files (Content-Based Deduplication)...")
    files_copied = 0

    for match in PATH_PATTERN.finditer(content):
        raw_path = match.group(1) or match.group(2) or match.group(3)
        real_path = resolve(raw_path)
        
        # If valid file AND we haven't mapped this exact path object yet
        if real_path and real_path not in real_path_map:
            fname = real_path.name
            
            # Skip the Tcl script itself
            if real_path == tcl_file: continue

            final_name = None
            
            # --- DEDUPLICATION LOGIC ---
            # Check if we already have a file with this name in destination
            if fname in dest_inventory:
                # Check content against ALL existing versions (file.v, file_2.v, etc)
                for existing_dest_path in dest_inventory[fname]:
                    if filecmp.cmp(real_path, existing_dest_path, shallow=False):
                        # CONTENT MATCH! It's the same file. Don't copy.
                        final_name = existing_dest_path.name
                        break
            
            # If no content match found, create a new copy
            if final_name is None:
                # Calculate unique name
                if fname not in dest_inventory:
                    final_name = fname
                else:
                    # Start counting at 2
                    cnt = 2
                    while True:
                        candidate = f"{real_path.stem}_{cnt}{real_path.suffix}"
                        if not (dest_dir / candidate).exists():
                            final_name = candidate
                            break
                        cnt += 1
                
                # Copy the file
                try:
                    target = dest_dir / final_name
                    shutil.copy2(real_path, target)
                    files_copied += 1
                    
                    if fname not in dest_inventory: dest_inventory[fname] = []
                    dest_inventory[fname].append(target)
                    
                except Exception as e:
                    print(f"[WARN] Failed to copy {fname}: {e}")
                    final_name = fname 

            # Register the mapping
            real_path_map[real_path] = final_name
            if fname not in suffix_lookup: suffix_lookup[fname] = []
            suffix_lookup[fname].append(real_path)

    # ----------------------------------------------------------------------
    # PASS 2: UPDATE TCL
    # ----------------------------------------------------------------------
    print("[INFO] Pass 2: Updating Tcl references...")
    
    def replacement_handler(match):
        raw_path = match.group(1) or match.group(2) or match.group(3)
        real_path = resolve(raw_path)
        target_name = None

        if real_path and real_path in real_path_map:
            target_name = real_path_map[real_path]
        elif not real_path:
            # Suffix Match for broken paths
            fname = Path(raw_path).name
            if fname in suffix_lookup:
                candidates = suffix_lookup[fname]
                raw_parts = Path(raw_path).parts
                best_cand = candidates[0]
                best_score = -1
                for cand in candidates:
                    cand_parts = cand.parts
                    score = 0
                    for i in range(1, min(len(raw_parts), len(cand_parts)) + 1):
                        if raw_parts[-i] == cand_parts[-i]: score += 1
                        else: break
                    if score > best_score:
                        best_score = score
                        best_cand = cand
                target_name = real_path_map[best_cand]

        if target_name:
            return f'"{SRC_DEST_DIR_NAME}/{target_name}"'

        return match.group(0)

    new_content = PATH_PATTERN.sub(replacement_handler, content)
    
    with open(tcl_file, 'w', encoding='utf-8') as f:
        f.write(new_content)

    if backup_dir.exists(): shutil.rmtree(backup_dir, ignore_errors=True)
    print(f"[SUCCESS] Copied {files_copied} unique files.")
    print(f"[SUCCESS] Tcl updated.")

# ==============================================================================
# UTILS
# ==============================================================================
def generate_gitignore(tcl_file):
    with open(tcl_file, 'r' , encoding='utf-8') as f: c = f.read()
    ip_dirs = set()
    m = re.search(r'set_property\s+["\{]ip_repo_paths["\}]\s+(.+?)\s+\$obj', c, re.DOTALL|re.IGNORECASE)
    if m: 
        for p in re.findall(r'\$origin_dir/([^"\]\s]+)', m.group(1)): ip_dirs.add(Path(p).parts[0])
    
    with open(".gitignore", 'w') as f:
        f.write(f"*\n!.gitignore\n!{Path(tcl_file).name}\n!run_vivado_export.tcl\n!{Path(__file__).name}\n")
        f.write("!readme.md\n!*.zip\n!rebuild_vitis.tcl\n")
        f.write(f"!{SRC_DEST_DIR_NAME}/\n!{SRC_DEST_DIR_NAME}/**\n")
        for d in sorted(ip_dirs): f.write(f"!{d}/\n!{d}/**\n")

if __name__ == "__main__":
    if len(sys.argv) > 1:
        consolidate_sources(sys.argv[1])
        generate_gitignore(sys.argv[1])
    else: print("[ERROR] Missing Tcl argument.")