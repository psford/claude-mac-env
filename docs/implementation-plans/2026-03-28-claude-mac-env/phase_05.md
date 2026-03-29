# Claude Mac Environment Implementation Plan — Phase 5

**Goal:** Build the dependency detection and CLI-first installation portion of `setup.sh` so a fresh Apple Silicon Mac goes from zero to all prerequisites installed.

**Architecture:** Shell script with preflight functions for each dependency. Each check follows: detect → ask permission → install via Homebrew → verify → fallback if needed. Apple Silicon gate first. Informed by install friction log at `docs/install-notes.md`.

**Tech Stack:** Bash, Homebrew, brew cask, gh CLI, macOS `uname`/`sysctl` for arch detection

**Scope:** Phase 5 of 8 from original design

**Codebase verified:** 2026-03-29 — Dockerfile and .devcontainer/devcontainer.json exist from Phase 1. No setup.sh exists yet. Install friction log at docs/install-notes.md documents known gotchas (brew link failures, gh auth setup-git needed separately).

---

## Acceptance Criteria Coverage

### claude-mac-env.AC1: Bootstrap installs dependencies CLI-first
- **claude-mac-env.AC1.1 Success:** Homebrew installed non-interactively when missing
- **claude-mac-env.AC1.2 Success:** Docker Desktop installed via brew cask when missing (with user permission)
- **claude-mac-env.AC1.3 Success:** VS Code installed via brew cask when missing (with user permission)
- **claude-mac-env.AC1.4 Success:** Dev Containers extension auto-installed via code CLI
- **claude-mac-env.AC1.5 Success:** All preflight checks pass silently on fully-equipped Mac
- **claude-mac-env.AC1.6 Failure:** Script exits with clear message on Intel Mac
- **claude-mac-env.AC1.7 Edge:** User declines VS Code install — script continues (non-blocking)

---

<!-- START_TASK_1 -->
### Task 1: Create setup.sh with architecture gate and utility functions

**Files:**
- Create: `setup.sh`

**Implementation:**

Create the script skeleton with:
- Shebang (`#!/usr/bin/env bash`), `set -euo pipefail`
- Color output utility functions (`info`, `warn`, `error`, `success`, `ask_yn`)
- Apple Silicon detection using `uname -m` (must be `arm64`)
- If Intel (`x86_64`): print clear message explaining Apple Silicon is required and exit 1
- Print welcome banner with version

The `ask_yn` function should:
- Accept a prompt string and default (y/n)
- Return 0 for yes, 1 for no
- Handle upper/lowercase input

**Verification:**

Run: `bash setup.sh` on an Apple Silicon Mac
Expected: Welcome banner prints, architecture check passes, script continues (and fails on next check since it's incomplete — that's fine for this task)

Run: `arch -x86_64 bash setup.sh` (simulate Intel)
Expected: Error message about Apple Silicon requirement, exit code 1

**Commit:** `feat: add setup.sh skeleton with Apple Silicon gate`
<!-- END_TASK_1 -->

<!-- START_TASK_2 -->
### Task 2: Add Homebrew preflight check

**Verifies:** claude-mac-env.AC1.1

**Files:**
- Modify: `setup.sh`

**Implementation:**

Add `check_homebrew()` function that:
1. Checks if `brew` command exists in PATH
2. Also checks `/opt/homebrew/bin/brew` (Apple Silicon default) and `/usr/local/bin/brew` (legacy)
3. If found: print success, ensure it's in PATH for this session
4. If not found: explain what Homebrew is, ask permission (`ask_yn`), install with `NONINTERACTIVE=1 /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"`
5. After install: add to PATH for current session (`eval "$(/opt/homebrew/bin/brew shellenv)"`)
6. Verify: `brew --version`
7. If install fails: print error with manual install URL, exit 1

Call `check_homebrew` from main flow after architecture check.

**Verification:**

Run on Mac with Homebrew: check passes silently
Run on Mac without Homebrew: prompts for permission, installs if yes

**Commit:** `feat: add Homebrew preflight check to setup.sh`
<!-- END_TASK_2 -->

<!-- START_TASK_3 -->
### Task 3: Add Xcode CLT and git preflight check

**Files:**
- Modify: `setup.sh`

**Implementation:**

Add `check_xcode_clt()` function that:
1. Checks if Xcode CLT is installed: `xcode-select -p &>/dev/null`
2. If installed: print success, verify git works (`git --version`)
3. If not installed: attempt `xcode-select --install` (this opens a GUI dialog — unavoidable)
4. Print message: "A dialog has appeared to install Xcode Command Line Tools. Please click Install and wait for completion, then press Enter to continue."
5. Wait for user to press Enter
6. Re-check `xcode-select -p` — if still not installed, exit with error

**Verification:**

Run on Mac with CLT: passes silently
Run on Mac without CLT: triggers install dialog, waits for user

**Commit:** `feat: add Xcode CLT preflight check to setup.sh`
<!-- END_TASK_3 -->

<!-- START_TASK_4 -->
### Task 4: Add Docker Desktop preflight check

**Verifies:** claude-mac-env.AC1.2

**Files:**
- Modify: `setup.sh`

**Implementation:**

Add `check_docker()` function that:
1. Check if `docker` command exists AND Docker daemon is running (`docker info &>/dev/null`)
2. If docker command exists but daemon not running: prompt user to start Docker Desktop, wait and retry (up to 30 seconds)
3. If docker not installed: explain what Docker Desktop is, ask permission (`ask_yn`), install via `brew install --cask docker --no-quarantine`
4. After brew install: handle `brew link` failures per friction log — if link fails, manually symlink the binary
5. Verify docker binary works: `docker --version`
6. Start Docker Desktop: `open -a Docker`
7. Wait for daemon: loop checking `docker info` with 2-second sleeps, timeout after 60 seconds
8. If timeout: print message about first-launch privilege prompt, ask user to authorize manually
9. Verify: `docker info` succeeds

**Verification:**

Run with Docker installed and running: passes silently
Run without Docker: prompts, installs, starts, waits for daemon

**Commit:** `feat: add Docker Desktop preflight check to setup.sh`
<!-- END_TASK_4 -->

<!-- START_TASK_5 -->
### Task 5: Add VS Code preflight check (non-blocking)

**Verifies:** claude-mac-env.AC1.3, claude-mac-env.AC1.7

**Files:**
- Modify: `setup.sh`

**Implementation:**

Add `check_vscode()` function that:
1. Check if `code` command exists in PATH
2. Also check common locations: `/usr/local/bin/code`, `/Applications/Visual Studio Code.app/Contents/Resources/app/bin/code`
3. If found: print success, return 0
4. If not found: explain VS Code is recommended but optional, ask permission
5. If user says yes: `brew install --cask visual-studio-code --no-quarantine`, handle link failures per friction log
6. If user says no: print "Skipping VS Code. You can install later and use 'Reopen in Container' to connect." Return 0 (non-blocking)
7. Set global variable `VSCODE_INSTALLED=true/false` for later use

**Verification:**

Run with VS Code: passes silently
Run without, user says yes: installs
Run without, user says no: continues without error

**Commit:** `feat: add VS Code preflight check (non-blocking) to setup.sh`
<!-- END_TASK_5 -->

<!-- START_TASK_6 -->
### Task 6: Add Dev Containers extension and gh CLI preflight checks

**Verifies:** claude-mac-env.AC1.4

**Files:**
- Modify: `setup.sh`

**Implementation:**

Add `check_devcontainers_extension()` function:
1. Only run if `VSCODE_INSTALLED=true`
2. Check if extension installed: `code --list-extensions 2>/dev/null | grep -qi "ms-vscode-remote.remote-containers"`
3. If installed: print success
4. If not: auto-install without asking: `code --install-extension ms-vscode-remote.remote-containers`
5. Verify: re-check extension list

Add `check_gh_cli()` function:
1. Check if `gh` command exists
2. If not: ask permission, `brew install gh`, handle link failures per friction log
3. Check auth: `gh auth status &>/dev/null`
4. If not authenticated: explain OAuth flow, run `gh auth login --web --git-protocol https`
5. After auth: run `gh auth setup-git` (per friction log — this is a separate required step)
6. Check git identity: `git config --global user.name` and `git config --global user.email`
7. If not set: offer to pull from GitHub profile (`gh api user --jq '.name // .login'`) or prompt manually
8. Configure: `git config --global user.name "..."` and `git config --global user.email "..."`

**Verification:**

Run with everything installed: passes silently
Run without extension + with VS Code: auto-installs extension
Run without gh: prompts, installs, authenticates

**Commit:** `feat: add Dev Containers extension and gh CLI preflight to setup.sh`
<!-- END_TASK_6 -->

<!-- START_TASK_7 -->
### Task 7: Wire up preflight flow and add summary

**Verifies:** claude-mac-env.AC1.5

**Files:**
- Modify: `setup.sh`

**Implementation:**

Add `run_preflight()` function that calls all checks in order:
1. `check_architecture` (hard stop if Intel)
2. `check_homebrew` (hard stop if fails)
3. `check_xcode_clt` (hard stop if fails)
4. `check_docker` (hard stop if fails)
5. `check_vscode` (non-blocking)
6. `check_devcontainers_extension` (only if VS Code installed)
7. `check_gh_cli` (hard stop if fails — needed for later phases)

After all checks pass, print summary:
```
✓ Preflight complete. All dependencies installed:
  • Homebrew [version]
  • Docker Desktop [version]
  • VS Code [version or "skipped"]
  • Dev Containers extension [installed or "skipped"]
  • gh CLI [version]
  • Git identity: [name] <[email]>
```

Add `--preflight-only` flag support: if passed, run preflight and exit (useful for testing).

Wire `run_preflight` into the main script flow.

**Verification:**

Run: `shellcheck setup.sh`
Expected: No errors (warnings acceptable for now, will be cleaned in Phase 8)

Run `bash setup.sh --preflight-only` on fully-equipped Mac:
Expected: All checks pass silently, summary printed, exit 0

Run `bash setup.sh --preflight-only` on Mac missing some tools:
Expected: Prompts for each missing tool, installs, summary printed

Note: All preflight checks are idempotent — re-running setup.sh safely skips already-installed tools. If setup fails partway, the user can simply re-run and it picks up where it left off.

**Commit:** `feat: wire up preflight flow with summary in setup.sh`
<!-- END_TASK_7 -->
