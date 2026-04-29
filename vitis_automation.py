import sys
import os
import zipfile
from pathlib import Path

# .metadata remains in the ignored directories list
VITIS_IGNORED_DIRS = {'Debug', 'Release', 'Hardware', 'export', '.Xil', '.ipcache', '.git', '.metadata'}

def get_local_repos(ws_path):
    """Parses preferences to find local repos without copying them to the workspace."""
    possible_paths = [
        ws_path / ".metadata" / ".plugins" / "org.eclipse.core.runtime" / ".settings" / "com.xilinx.sdk.sw.prefs",
        ws_path / ".metadata" / ".plugins" / "com.xilinx.sdk.sw.prefs"
    ]
    
    prefs_file = next((p for p in possible_paths if p.exists()), None)
    
    if not prefs_file:
        print("[INFO] No Vitis local repo preferences found.")
        return []

    print(f"[INFO] Found Vitis preferences: {prefs_file.name}")
    local_repos = []

    try:
        with open(prefs_file, 'r', encoding='utf-8', errors='ignore') as f:
            for line in f:
                if "com.xilinx.sdk.sw.prefs.repos.local" in line:
                    # Value format: key=C\:/Path/To/Repo;D\:/Path;
                    parts = line.split('=', 1)
                    if len(parts) > 1:
                        # Fix escaped Windows drives (C\: -> C:)
                        raw_val = parts[1].strip().replace('\\:', ':')
                        paths = raw_val.split(';')
                        for p in paths:
                            if p.strip(): local_repos.append(Path(p.strip()))
    except Exception as e:
        print(f"[WARN] Failed to parse Vitis prefs: {e}")
        return []

    return local_repos

def run_export(ws_path_str):
    ws_path = Path(ws_path_str).resolve()
    
    if not ws_path.exists() or not ws_path.is_dir():
        print(f"[ERROR] Invalid workspace path provided: {ws_path}")
        return

    # 1. Gather local repos paths and resolve them immediately
    local_repos = get_local_repos(ws_path)
    resolved_repos = [p.resolve() for p in local_repos]
    
    # 2. Zip Workspace
    zip_name = ws_path.parent / f"{ws_path.name}_export.zip"
    print(f"[INFO] Zipping workspace into {zip_name} (Ignoring .metadata)...")
    
    with zipfile.ZipFile(zip_name, 'w', zipfile.ZIP_DEFLATED) as zf:
        # Walk the main workspace directory
        for r, ds, fs in os.walk(ws_path):
            current_dir = Path(r).resolve()
            
            # Filter out ignored Vitis directories in place
            ds[:] = [d for d in ds if d not in VITIS_IGNORED_DIRS]
            
            # EXCLUSION LOGIC: Prevent zipping local repos in their original workspace location
            # This stops a repo from being zipped twice if it physically resides inside the workspace.
            ds[:] = [d for d in ds if (current_dir / d).resolve() not in resolved_repos]
            
            for x in fs:
                file_path = Path(r) / x
                
                # Safeguard: don't zip the zip file if it somehow ends up in the path
                if file_path.resolve() == zip_name.resolve():
                    continue
                    
                # Write to zip
                try:
                    zf.write(file_path, file_path.relative_to(ws_path))
                except PermissionError:
                    print(f"[WARN] Skipping locked file (Permission Denied): {file_path.relative_to(ws_path)}")
                except Exception as e:
                    print(f"[WARN] Failed to zip {file_path.relative_to(ws_path)}: {e}")
        
        # 3. Walk ALL repos (external AND internal) and inject them directly into the zip archive
        for resolved_repo in resolved_repos:
            try:
                if not resolved_repo.exists() or not resolved_repo.is_dir():
                    print(f"[WARN] Local repo path invalid or missing: {resolved_repo}")
                    continue
                    
                print(f"[INFO] Injecting repo into zip at imported_local_repos/{resolved_repo.name}: {resolved_repo}")
                
                for repo_r, repo_ds, repo_fs in os.walk(resolved_repo):
                    for x in repo_fs:
                        file_path = Path(repo_r) / x
                        
                        # Map it virtually inside the zip: imported_local_repos/<repo_name>/...
                        relative_to_repo = file_path.relative_to(resolved_repo)
                        zip_path = Path("imported_local_repos") / resolved_repo.name / relative_to_repo
                        
                        try:
                            zf.write(file_path, zip_path)
                        except PermissionError:
                            print(f"[WARN] Skipping locked file in repo (Permission Denied): {file_path}")
                        except Exception as e:
                            print(f"[WARN] Failed to zip repo file {file_path}: {e}")
                            
            except Exception as e:
                print(f"[WARN] Failed to process repo {resolved_repo}: {e}")
                
    print(f"[SUCCESS] Export complete.")

if __name__ == "__main__":
    # The Tcl script passes the workspace path as the first argument
    if len(sys.argv) > 1:
        run_export(sys.argv[1])
    else:
        print("[ERROR] Workspace path argument missing. Run this via the Tcl script.")