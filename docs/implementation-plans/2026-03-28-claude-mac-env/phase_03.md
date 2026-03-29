# Claude Mac Environment Implementation Plan — Phase 3

**Goal:** Package the `csharp-tools` and `psford-personal` tooling tiers as Dev Container Features with proper distro detection and feature options.

**Architecture:** Same Feature structure as Phase 2. `csharp-tools` includes .NET SDK installation (distro-aware) and C#-specific hooks. `psford-personal` includes project-specific guards and helpers. Both use `installsAfter` for ordering.

**Tech Stack:** Dev Container Features spec, .NET SDK, detect-package-manager.sh from base image

**Scope:** Phase 3 of 8 from original design

**Codebase verified:** 2026-03-29 — features/claude-skills/ and features/universal-hooks/ exist from Phase 2. GitHub Actions publish workflow exists. claude-env repo contains: dotnet_process_guard.py, ef_migration_guard.py (C#-specific), 22 project-specific guards, Stream Deck/Slack/PowerShell helpers (psford-specific).

---

## Acceptance Criteria Coverage

### claude-mac-env.AC4: Dev Container Features (remaining)
- **claude-mac-env.AC4.3 Success:** csharp-tools Feature installs .NET SDK at configured version
- **claude-mac-env.AC4.4 Success:** psford-personal Feature installs all personal tooling
- **claude-mac-env.AC4.6 Edge:** Feature install on non-Ubuntu distro uses correct package manager

---

<!-- START_SUBCOMPONENT_A (tasks 1-2) -->
<!-- START_TASK_1 -->
### Task 1: Create csharp-tools Feature

**Verifies:** claude-mac-env.AC4.3, claude-mac-env.AC4.6

**Files:**
- Create: `features/csharp-tools/devcontainer-feature.json`
- Create: `features/csharp-tools/install.sh`
- Create: `features/csharp-tools/hooks/dotnet_process_guard.py`
- Create: `features/csharp-tools/hooks/ef_migration_guard.py`

**Implementation:**

`devcontainer-feature.json`:
```json
{
  "id": "csharp-tools",
  "version": "1.0.0",
  "name": "C# / .NET Development Tools",
  "description": "Installs .NET SDK, Entity Framework migration hooks, and C# development helpers",
  "options": {
    "dotnetVersion": {
      "type": "string",
      "proposals": ["9.0", "8.0", "10.0"],
      "default": "9.0",
      "description": ".NET SDK version to install"
    }
  },
  "installsAfter": [
    "ghcr.io/psford/claude-mac-env/universal-hooks"
  ]
}
```

`install.sh`:
1. Source `detect-package-manager.sh` from base image
2. Based on package manager:
   - `apt`: Add Microsoft package repository for Ubuntu/Debian, install `dotnet-sdk-${DOTNETVERSION}`
   - `dnf`: Add Microsoft repo for Fedora/RHEL, install via dnf
   - `apk`: Install from Alpine community packages or Microsoft feed
3. Install EF tools globally: `dotnet tool install --global dotnet-ef`
4. Copy hook scripts to Claude Code hooks directory (`$_REMOTE_USER_HOME/.claude/hooks/`)
5. Verify: `dotnet --version`, `dotnet ef --version`

Hook scripts sourced from claude-env:
- `dotnet_process_guard.py` — monitors .NET process operations
- `ef_migration_guard.py` — enforces EF migration discipline on model changes

**Testing:**

Build container with feature on default Ubuntu:
```bash
dotnet --version  # Should show configured version
dotnet ef --version  # Should be available
```

Also build with non-Ubuntu distro to verify AC4.6:
```bash
docker build --build-arg BASE_IMAGE=fedora:40 -t claude-mac-env:fedora .
```
Then rebuild container with Fedora base and verify `dotnet --version` works (installed via dnf, not apt).

**Commit:** `feat: add csharp-tools Dev Container Feature`
<!-- END_TASK_1 -->

<!-- START_TASK_2 -->
### Task 2: Create psford-personal Feature

**Verifies:** claude-mac-env.AC4.4

**Files:**
- Create: `features/psford-personal/devcontainer-feature.json`
- Create: `features/psford-personal/install.sh`
- Create: `features/psford-personal/hooks/` (22 project-specific guard files)
- Create: `features/psford-personal/helpers/` (psford-specific helper scripts)

**Implementation:**

`devcontainer-feature.json`:
```json
{
  "id": "psford-personal",
  "version": "1.0.0",
  "name": "psford Personal Development Tools",
  "description": "Project-specific guards, Slack integration, Stream Deck assets, and Azure tooling for psford",
  "options": {
    "installAzureCli": {
      "type": "boolean",
      "default": true,
      "description": "Install Azure CLI for Key Vault and deployment tooling"
    }
  },
  "installsAfter": [
    "ghcr.io/psford/claude-mac-env/universal-hooks",
    "ghcr.io/psford/claude-mac-env/csharp-tools"
  ]
}
```

`install.sh`:
1. Source `detect-package-manager.sh`
2. If `$INSTALLAZURECLI` is true: install Azure CLI via package manager
3. Install Python dependencies needed by helpers: `pip3 install slack-bolt slack-sdk requests anthropic`
4. Copy 22 project-specific guard scripts to `$_REMOTE_USER_HOME/.claude/hooks/`
5. Copy psford-specific helpers to `$_REMOTE_USER_HOME/.claude/helpers/`:
   - `test_docs_tabs.py`, `test_hover_images.py`
   - `generate_stream_deck_icons.py`
   - `Invoke-SpeechToText.ps1`
   - Slack integration suite (`slack_notify.py`, `slack_acknowledger.py`, `slack_bot.py`, `slack_listener.py`, `slack_file_download.py`)
6. Verify Azure CLI if installed: `az --version`

Project-specific guards from claude-env (all 22):
- ac_staleness_guard.py, artifact_path_guard.py, assert_verify_guard.py, constant_change_test_guard.py, deploy_guard.py, deprecation_guard.py, eodhd_rebuild_guard.py, fix_commit_smell_guard.py, js_module_coverage_guard.py, js_test_theater_guard.py, library_intro_guard.py, merged_pr_guard.py, mock_test_guard.py, plan_commit_guard.py, plan_phase_count_guard.py, post_push_pr_check.py, prices_scan_guard.py, retro_trigger_guard.py, session_start.py, stderr_suppression_guard.py, workaround_guard.py, plan_config_drift_guard.py

**Testing:**

Build container with all four Features. Verify guards are in hooks directory, helpers are accessible, Azure CLI works.

**Commit:** `feat: add psford-personal Dev Container Feature`
<!-- END_TASK_2 -->
<!-- END_SUBCOMPONENT_A -->

<!-- START_TASK_3 -->
### Task 3: Update devcontainer.json and verify all four Features together

**Files:**
- Modify: `.devcontainer/devcontainer.json`

**Implementation:**

Add the two new local Features:
```json
"features": {
  "./features/claude-skills": {},
  "./features/universal-hooks": {},
  "./features/csharp-tools": { "dotnetVersion": "9.0" },
  "./features/psford-personal": { "installAzureCli": true }
}
```

**Verification:**

Rebuild container. Inside container verify:
```bash
dotnet --version        # .NET 9.0
dotnet ef --version     # EF tools available
az --version            # Azure CLI
ls ~/.claude/hooks/     # All guards present
ls ~/.claude/helpers/   # psford helpers present
claude --version        # Still works with all features
```

**Commit:** `feat: integrate all four Dev Container Features`
<!-- END_TASK_3 -->

<!-- START_TASK_4 -->
### Task 4: Verify Feature publishing includes new Features

**Files:**
- No changes (workflow from Phase 2 auto-discovers features in `features/` directory)

**Verification:**

Push a test tag to trigger publishing workflow. Verify all four Features appear in GHCR:
- `ghcr.io/psford/claude-mac-env/claude-skills`
- `ghcr.io/psford/claude-mac-env/universal-hooks`
- `ghcr.io/psford/claude-mac-env/csharp-tools`
- `ghcr.io/psford/claude-mac-env/psford-personal`

Set all packages to public visibility in GitHub Package settings.

**Commit:** No commit — verification only.
<!-- END_TASK_4 -->
