# 🚀 Vitis & Vivado Workspace Export / Import Guide

This guide describes an automated version control approach for Vitis and Vivado projects.

---

# 📋 Prerequisites

Before starting, make sure the following requirements are met:

### 🔧 Required Files

* `run_vitis_export.tcl`
* `vitis_automation.py`
* `rebuild_vitis.tcl`
* `run_vivado_export.tcl`
* `vivado_automation.py`

### 🧰 Tools & Environment

* **Xilinx Vivado / Vitis:** Version **2023.1** (must be consistent across the team)
* **Python 3.x:** Installed and added to system `PATH`
* **Unique Source Names** No two files with different content should share the same filename
* **Constraint Management**  Use separate constraint sets, Each set should contain **only one constraint file**
* **Board Files** Ensure required board files are installed via: Vivado Board Store


### ⚠️ Important Rules

* **Automation Only:**
  Do **not** manually create `.tcl` scripts or `.gitignore` files.
  Always use the provided automation scripts to maintain consistency.

---

# 🧠 VITIS WORKFLOW

suitable for single-platform vitis workspace.
## 📤 Exporting a project

1. Copy the following files into your Vitis workspace directory:

   * `run_vitis_export.tcl`
   * `vitis_automation.py`

2. Open  **XSCT Console** 
   
   `VITIS IDE-> window → XSCT Console`

3. Run the export script:

   ```tcl
   cd <vitis_workspace>
   source run_vitis_export.tcl
   ```

4. ✅ **Output:**
   A zip archive named:

   ```
   <workspace_name>_export.zip
   ```

   will be created in the workspace’s parent folder.

---

## 📥 Rebuilding a Vitis project 

1. Ensure:

   * `rebuild_vitis.tcl` is in the **same directory** as the exported `.zip`

2. Launch:

   ```
   xsct.bat
   ```

   (Typically located in `/Xilinx/Vitis/2023.1/bin`)

3. Run:

   ```tcl
   cd <path to cloned directory:>
   source rebuild_vitis.tcl
   ```

4. ✅ **Result:**

   * A new workspace is automatically created
   * Open Vitis and select the newly generated workspace

---

# 🧩 VIVADO WORKFLOW


## 📤 Exporting a Vivado Project

1. Place in project root directory:

   * `run_vivado_export.tcl`
   * `vivado_automation.py`

2. Open the project in **Vivado**

3. Open **Tcl Console**

4. Run:

   ```tcl
   source run_vivado_export.tcl
   ```

5. ✅ **Result:**

   * Export package + rebuild script are generated

---

## 📥 Rebuilding a Vivado Project

1. Open **Vivado**

2. Open **Tcl Console**

3. Navigate to the cloned directory:

   ```tcl
   cd <project_directory>
   ```

4. Run:

   ```tcl
   source Vivado_project_rebuild.tcl
   ```

5. ✅ **Result:**

   * Project is fully reconstructed with correct settings and sources


---

# 📦 Summary
```
Unified_Project_Root_directory/
│
├── run_vivado_export.tcl
├── vivado_automation.py
├── Vivado_project_rebuild.tcl (Auto-generated)
├── tcl_imported_src (Auto-generated)
├── tcl_imported_ips (Auto-generated)
├── .gitignore (Auto-generated)
│
├── rebuild_vitis.tcl
├── <workspace_name>_export.zip (Auto-generated)
└── vitis_workspace_directory/
    ├── run_vitis_export.tcl
    └── vitis_automation.py
```
vitis workspace can be seperated of nested in the vivado root directory.


| Task             | Tool   | Script                       |
| ---------------- | ------ | ---------------------------- |
| Export Workspace | Vitis  | `run_vitis_export.tcl`       |
| Import Workspace | Vitis  | `rebuild_vitis.tcl`          |
| Export Project   | Vivado | `run_vivado_export.tcl`      |
| Import Project   | Vivado | `Vivado_project_rebuild.tcl`(auto-generated) |

---
