---
description: "Project Workflow and Tooling Guidelines"
trigger: always_on
---

# HorseCollisionMod Workflow

**CRITICAL INSTRUCTION**: NEVER use raw git commands (`git status`, `git commit`, `git branch`, `git checkout`, `git merge`, `git push`) or manually update version numbers and releases. 

This project uses a custom PowerShell workflow script (`tools/flow.ps1`) for EVERYTHING to ensure linters run, versions are correctly bumped, and documentation is updated consistently.

## Flow Tool Usage
- **Status**: Check where everything stands (branch, test world, install)
  ```powershell
  .\tools\flow.ps1 status
  ```
- **Test**: Get into or back into a testable state.
  ```powershell
  .\tools\flow.ps1 test
  ```
- **Branch**: Start a new branch and get testable.
  ```powershell
  .\tools\flow.ps1 branch <branch_name>
  ```
- **Land**: Finish work, run style checks, bump versions, commit, merge, tag, and push.
  ```powershell
  .\tools\flow.ps1 land "your commit message here"
  ```
- **Shipping**: Park the mod to test a release build.
  ```powershell
  .\tools\flow.ps1 shipping
  ```

Always rely on `flow.ps1` for managing branches and landing commits!
