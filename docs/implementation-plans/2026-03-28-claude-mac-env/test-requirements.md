# Test Requirements — claude-mac-env

Maps each acceptance criterion to either an automated validation or a documented human verification procedure.

**Test infrastructure context:** This is a shell-script and Docker infrastructure project. "Automated tests" means validation scripts (primarily `scripts/validate.sh`), CI pipeline checks (`.github/workflows/ci.yml`), and small focused bash verification scripts — not xUnit-style test frameworks. Many criteria involve GUI interactions (VS Code Dev Containers), hardware-specific behavior (Apple Silicon), or external services (GHCR, Azure Key Vault) that require human verification.

---

## AC1: Bootstrap installs dependencies CLI-first

### AC1.1 — Homebrew installed non-interactively when missing

| Field | Value |
|---|---|
| **Test type** | Script |
| **Test file** | `scripts/test-preflight.sh` |
| **Description** | On a system without Homebrew: run `setup.sh --preflight-only` and assert that `brew --version` succeeds after the script completes. On a system with Homebrew: assert the script does not re-install and exits the check silently (exit 0, no install output). |
| **CI coverage** | Not automatable in CI (GitHub Actions runners have Homebrew pre-installed; cannot test the missing-Homebrew path without a bare macOS image). |
| **Human verification** | Required for the "missing Homebrew" path. Run `setup.sh` on a Mac where `/opt/homebrew/bin/brew` has been temporarily renamed. Confirm the script offers to install, installs with `NONINTERACTIVE=1`, and `brew --version` works afterward. |

### AC1.2 — Docker Desktop installed via brew cask when missing (with user permission)

| Field | Value |
|---|---|
| **Test type** | Human verification |
| **Justification** | Docker Desktop installation requires macOS GUI privilege prompts (kernel extensions, network filter), first-launch authorization, and daemon startup — none of which can run headlessly in CI. |
| **Procedure** | 1. Uninstall Docker Desktop (`brew uninstall --cask docker`). 2. Run `setup.sh --preflight-only`. 3. Confirm the script explains Docker Desktop and asks permission (y/n). 4. Answer yes. 5. Confirm `brew install --cask docker` runs. 6. Confirm the script waits for the Docker daemon to become ready. 7. Confirm `docker info` succeeds after the script completes. |

### AC1.3 — VS Code installed via brew cask when missing (with user permission)

| Field | Value |
|---|---|
| **Test type** | Human verification |
| **Justification** | VS Code cask install includes macOS quarantine handling and app bundle registration that require a desktop environment. |
| **Procedure** | 1. Uninstall VS Code (`brew uninstall --cask visual-studio-code`). 2. Run `setup.sh --preflight-only`. 3. Confirm the script asks permission. 4. Answer yes. 5. Confirm `code --version` succeeds afterward. |

### AC1.4 — Dev Containers extension auto-installed via code CLI

| Field | Value |
|---|---|
| **Test type** | Script |
| **Test file** | `scripts/test-preflight.sh` |
| **Description** | With VS Code installed, assert `code --list-extensions` includes `ms-vscode-remote.remote-containers` after `setup.sh --preflight-only` completes. If the extension was already present, assert no reinstall attempt. |
| **CI coverage** | Not automatable in CI (no VS Code on GitHub Actions runners). |
| **Human verification fallback** | Run `code --uninstall-extension ms-vscode-remote.remote-containers`, then run `setup.sh --preflight-only`. Confirm the extension is reinstalled silently. |

### AC1.5 — All preflight checks pass silently on fully-equipped Mac

| Field | Value |
|---|---|
| **Test type** | Script |
| **Test file** | `scripts/test-preflight.sh` |
| **Description** | On a fully-equipped Mac (Homebrew, Docker, VS Code, Dev Containers extension, gh CLI all present), run `setup.sh --preflight-only`. Assert exit code 0 and that output contains no "Installing" lines — only the summary checklist. |
| **CI coverage** | Partial. CI can run `shellcheck setup.sh` to catch syntax/logic errors but cannot execute the actual preflight flow. |

### AC1.6 — Script exits with clear message on Intel Mac

| Field | Value |
|---|---|
| **Test type** | Script |
| **Test file** | `scripts/test-preflight.sh` |
| **Description** | Run `arch -x86_64 bash setup.sh` (simulates Intel `uname -m` returning `x86_64`). Assert exit code 1 and that stderr contains "Apple Silicon" in the error message. |
| **CI coverage** | Can be tested in CI on an `ubuntu-latest` runner (which reports `x86_64`) by running the architecture-check function in isolation. |

### AC1.7 — User declines VS Code install — script continues (non-blocking)

| Field | Value |
|---|---|
| **Test type** | Script |
| **Test file** | `scripts/test-preflight.sh` |
| **Description** | Pipe `n` to the VS Code install prompt (or use `CLAUDE_SETUP_VSCODE=skip` env var if the script supports non-interactive mode). Assert exit code 0 and that the summary shows "VS Code: skipped." |
| **Human verification fallback** | Run `setup.sh --preflight-only` without VS Code installed. Answer "no" at the VS Code prompt. Confirm the script proceeds to the next check without error. |

---

## AC2: Identity routing and tiered selection

### AC2.1 — GitHub username `psford` enables all Features without prompts

| Field | Value |
|---|---|
| **Test type** | Script |
| **Test file** | `scripts/test-identity-routing.sh` |
| **Description** | Source the `select_features()` function from `setup.sh` with `GITHUB_USER=psford`. Assert the resulting `SELECTED_FEATURES` JSON includes all four Features (`claude-skills`, `universal-hooks`, `csharp-tools`, `psford-personal`) and that no interactive prompt was issued (no reads from stdin). |

### AC2.2 — Other usernames see tiered selection from manifest

| Field | Value |
|---|---|
| **Test type** | Script |
| **Test file** | `scripts/test-identity-routing.sh` |
| **Description** | Source `select_features()` with `GITHUB_USER=testuser` and a local copy of `tooling-manifest.json`. Assert the script reads from stdin (prompts appear) and that the resulting Features depend on the simulated user responses. |

### AC2.3 — Universal tools presented with descriptions and y/n prompt

| Field | Value |
|---|---|
| **Test type** | Human verification |
| **Justification** | Verifying the quality and readability of interactive prompt text is a UX concern that requires human judgment. |
| **Procedure** | 1. Run `setup.sh` and enter a non-`psford` username. 2. Confirm the universal tier section lists each tool with a one-line description sourced from the manifest. 3. Confirm a single y/n prompt governs the entire universal tier. 4. Answer yes. Confirm `universal-hooks` appears in the generated `devcontainer.json`. |

### AC2.4 — Language tools grouped by language with y/n per group

| Field | Value |
|---|---|
| **Test type** | Human verification |
| **Justification** | Verifying the grouping and per-language prompt structure is a UX concern. |
| **Procedure** | 1. Run `setup.sh` with a non-`psford` username. 2. After the universal prompt, confirm language tools are grouped (e.g., "C# / .NET tools available:"). 3. Confirm each language group has its own y/n prompt. 4. Accept C# tools. 5. Confirm `csharp-tools` appears in `devcontainer.json` with the correct `.NET` version option. |

### AC2.5 — Personal tier never shown to non-psford users

| Field | Value |
|---|---|
| **Test type** | Script |
| **Test file** | `scripts/test-identity-routing.sh` |
| **Description** | Source `select_features()` with `GITHUB_USER=testuser` and pipe `y` to all prompts. Assert `psford-personal` does not appear in `SELECTED_FEATURES`. Grep `setup.sh` output for "personal" — should find no prompt text. |

### AC2.6 — Empty manifest gracefully installs only claude-skills

| Field | Value |
|---|---|
| **Test type** | Script |
| **Test file** | `scripts/test-identity-routing.sh` |
| **Description** | Source `select_features()` with `GITHUB_USER=testuser` and set the manifest URL to return an empty JSON (`{"version":"1.0","features":[],"tools":[]}`). Assert `SELECTED_FEATURES` contains only `claude-skills` and no errors are printed. |

---

## AC3: Container filesystem isolation

### AC3.1 — Project dirs writable from inside container

| Field | Value |
|---|---|
| **Test type** | Script (automated) |
| **Test file** | `scripts/validate.sh` |
| **Description** | Create a temp directory on the host, mount it RW into a container at `/workspaces/test`, run `docker run ... touch /workspaces/test/write-test && rm /workspaces/test/write-test`. Assert exit code 0. |

### AC3.2 — .gitconfig readable but not writable from container

| Field | Value |
|---|---|
| **Test type** | Script (automated) |
| **Test file** | `scripts/validate.sh` |
| **Description** | Mount a dummy `.gitconfig` file read-only into the container. Assert `cat` succeeds (exit 0). Assert `echo "x" >> /home/claude/.gitconfig` fails with a permission error (non-zero exit). |

### AC3.3 — .ssh readable but not writable from container

| Field | Value |
|---|---|
| **Test type** | Script (automated) |
| **Test file** | `scripts/validate.sh` |
| **Description** | Mount a dummy `.ssh` directory read-only. Assert `ls /home/claude/.ssh` succeeds. Assert `touch /home/claude/.ssh/test-file` fails with permission error. |

### AC3.4 — No other Mac paths visible inside container

| Field | Value |
|---|---|
| **Test type** | Script (automated) |
| **Test file** | `scripts/validate.sh` |
| **Description** | Run `docker run ... ls /Users 2>&1` and assert it fails (directory does not exist). Run `docker run ... ls /Volumes 2>&1` and assert it fails. Run `docker run ... mount` and assert no entries reference `/host` or macOS-specific paths. |

### AC3.5 — Write attempt to read-only mount fails with permission error

| Field | Value |
|---|---|
| **Test type** | Script (automated) |
| **Test file** | `scripts/validate.sh` |
| **Description** | Mount a file read-only, attempt to write. Assert the command exits non-zero and stderr contains "Read-only file system" or "Permission denied." |

---

## AC4: Dev Container Features

### AC4.1 — claude-skills Feature installs and skills are usable

| Field | Value |
|---|---|
| **Test type** | Integration (script + human) |
| **Test file** | `scripts/validate.sh` |
| **Automated portion** | Build the container with the `claude-skills` Feature. Assert the skills directory exists (`ls /home/claude/.claude/skills/` or equivalent) and is non-empty. Assert `claude --version` still works after Feature installation. |
| **Human verification** | Open VS Code, connect to the container, launch Claude Code in the terminal. Verify skills are listed and functional (e.g., run a skill command). |

### AC4.2 — universal-hooks Feature installs and hooks trigger on git ops

| Field | Value |
|---|---|
| **Test type** | Integration (script + human) |
| **Test file** | `scripts/validate.sh` |
| **Automated portion** | Build container with `universal-hooks` Feature. Assert hook files exist in the expected location (`/usr/local/share/claude-hooks/` or `/home/claude/.claude/hooks/`). Inside the container, run `git config --system core.hooksPath` and assert it returns the hooks directory. |
| **Human verification** | Inside the container terminal: `cd /workspaces && git init test-repo && cd test-repo && echo test > file.txt && git add . && git commit -m "test"`. Verify hook output appears (e.g., commit permission prompt or atomicity check). |

### AC4.3 — csharp-tools Feature installs .NET SDK at configured version

| Field | Value |
|---|---|
| **Test type** | Script (automated) |
| **Test file** | `scripts/validate.sh` |
| **Description** | Build container with `csharp-tools` Feature and `dotnetVersion=9.0`. Run `docker run ... dotnet --version` and assert output starts with `9.0`. Run `docker run ... dotnet ef --version` and assert it succeeds. |

### AC4.4 — psford-personal Feature installs all personal tooling

| Field | Value |
|---|---|
| **Test type** | Script (automated) |
| **Test file** | `scripts/validate.sh` |
| **Description** | Build container with all four Features. Assert all 22 project-specific guard files exist in `/home/claude/.claude/hooks/`. Assert helper scripts exist in `/home/claude/.claude/helpers/`. If `installAzureCli=true`, assert `az --version` succeeds. |

### AC4.5 — Features publish to GHCR via GitHub Actions

| Field | Value |
|---|---|
| **Test type** | CI (automated) |
| **Test file** | `.github/workflows/publish-features.yml` |
| **Description** | Push a version tag (`v*`). Assert the GitHub Actions workflow completes successfully. After workflow completes, assert all four Feature OCI artifacts exist on GHCR: `ghcr.io/psford/claude-mac-env/claude-skills`, `ghcr.io/psford/claude-mac-env/universal-hooks`, `ghcr.io/psford/claude-mac-env/csharp-tools`, `ghcr.io/psford/claude-mac-env/psford-personal`. |
| **Verification command** | `gh api /user/packages?package_type=container` or check GHCR web UI for published packages. |

### AC4.6 — Feature install on non-Ubuntu distro uses correct package manager

| Field | Value |
|---|---|
| **Test type** | Script (automated) |
| **Test file** | `scripts/test-distro-compat.sh` |
| **Description** | Build base image with `--build-arg BASE_IMAGE=fedora:40`. Run `detect-package-manager.sh` inside the container and assert output is `dnf`. Build with `csharp-tools` Feature and assert `dotnet --version` succeeds (installed via dnf, not apt). Repeat with `alpine:3.19` and assert `detect-package-manager.sh` returns `apk`. |
| **Note** | Full Feature installation on non-Ubuntu distros may require additional manual verification for edge cases in package availability. |

---

## AC5: Day-to-day and rebuild workflow

### AC5.1 — VS Code reconnects to existing container without rebuild

| Field | Value |
|---|---|
| **Test type** | Human verification |
| **Justification** | VS Code reconnection behavior is a GUI-only operation involving the Dev Containers extension's container lifecycle management. No CLI equivalent exists. |
| **Procedure** | 1. Open the project in VS Code and build the container (green indicator in bottom-left). 2. Close VS Code completely (`Cmd+Q`). 3. Reopen VS Code and open the same project folder. 4. Confirm VS Code reconnects to the existing container (green indicator reappears within seconds, no "Building container" progress bar). 5. Open a terminal and run `uptime` — confirm the container has been running since the original build, not freshly started. |

### AC5.2 — Claude Code runs and can edit files in /workspaces

| Field | Value |
|---|---|
| **Test type** | Script (automated) + Human verification |
| **Test file** | `scripts/validate.sh` |
| **Automated portion** | Run `docker run ... claude --version` and assert exit 0. Run `docker run ... bash -c "echo test > /workspaces/test-file && cat /workspaces/test-file && rm /workspaces/test-file"` and assert output is "test". |
| **Human verification** | Inside the VS Code container terminal, run `claude` and ask it to create a file in `/workspaces/`. Confirm the file appears in the VS Code file explorer and persists on the host. |

### AC5.3 — Container survives Mac sleep/wake cycle

| Field | Value |
|---|---|
| **Test type** | Human verification |
| **Justification** | Sleep/wake behavior is hardware-dependent and involves macOS power management, Docker Desktop's VM lifecycle, and container state persistence — none of which can be simulated in CI or scripted. |
| **Procedure** | 1. Open VS Code with the container running. 2. Close the laptop lid (sleep). 3. Wait at least 30 seconds. 4. Open the lid (wake). 5. Switch to VS Code. 6. Confirm the terminal still works (run `date`). 7. Confirm `claude --version` still responds. 8. If disconnected, confirm VS Code auto-reconnects within 10 seconds. |

### AC5.4 — 'Rebuild Container' reinstalls Features from GHCR

| Field | Value |
|---|---|
| **Test type** | Human verification |
| **Justification** | The "Rebuild Container" command is a VS Code Dev Containers extension UI action with no CLI equivalent for the full rebuild-and-reconnect cycle. |
| **Procedure** | 1. With the container running in VS Code, open the Command Palette (`Cmd+Shift+P`). 2. Run "Dev Containers: Rebuild Container". 3. Confirm the rebuild progress shows Feature installation (look for GHCR URLs in the build log). 4. After rebuild, confirm all Features are functional: `claude --version`, `dotnet --version` (if C# selected), hooks directory populated. |

### AC5.5 — Destroying container + re-running setup.sh restores full env

| Field | Value |
|---|---|
| **Test type** | Script (e2e) + Human verification |
| **Test file** | `scripts/validate.sh` |
| **Automated portion** | Run `docker rm -f $(docker ps -aq --filter ancestor=claude-mac-env)`, `docker rmi claude-mac-env:latest`, then run `setup.sh` (with pre-saved `.user-config.json` for non-interactive mode). Assert the image rebuilds and `scripts/validate.sh` passes. |
| **Human verification** | After the scripted nuke-and-pave, open VS Code and "Reopen in Container." Confirm the full environment is functional: Claude Code works, hooks are present, mounts are correct. |

---

## AC6: Manifest classification hook

### AC6.1 — New file in claude-env triggers classification agent

| Field | Value |
|---|---|
| **Test type** | Human verification |
| **Justification** | The classification agent is a Claude Code hook that invokes AI capabilities. It requires an active Claude Code session with API access and cannot be run headlessly. |
| **Procedure** | 1. In the `claude-env` repo, create a new file: `helpers/test_new_helper.py` with content that implements a generic utility (e.g., a JSON schema validator). 2. Stage it: `git add helpers/test_new_helper.py`. 3. Initiate a commit in Claude Code. 4. Confirm the manifest classification hook fires (output indicates it detected an uncatalogued file). 5. Clean up: remove the test file and revert manifest changes. |

### AC6.2 — Agent assigns tier, language, and Feature to new tool

| Field | Value |
|---|---|
| **Test type** | Human verification |
| **Justification** | The classification output depends on AI analysis of file content. Correctness of tier/language/Feature assignment requires human judgment. |
| **Procedure** | 1. Follow AC6.1 procedure through step 4. 2. Inspect the proposed manifest entry. 3. Confirm it includes: a valid `tier` value (`universal`, `language`, or `personal`), a `language` field (null or a recognized language string), a `feature` field referencing one of the four Features, and a meaningful `description`. 4. For a Python utility helper, expect `tier: "universal"`, `language: "python"` or `null`, `feature: "universal-hooks"`. |

### AC6.3 — Manifest diff shown for author review before push

| Field | Value |
|---|---|
| **Test type** | Human verification |
| **Justification** | Diff display is a UX behavior in the Claude Code terminal. |
| **Procedure** | 1. Follow AC6.1 procedure. 2. After the classification agent runs, confirm a diff of `tooling-manifest.json` is printed to the terminal showing the added entry. 3. Confirm the author has the opportunity to review and modify the entry before the commit proceeds. 4. The commit should not auto-complete — author must explicitly approve. |

### AC6.4 — Already-cataloged file changes don't duplicate manifest entries

| Field | Value |
|---|---|
| **Test type** | Script |
| **Test file** | `scripts/test-manifest-hook.sh` (in claude-env repo) |
| **Description** | Modify an existing cataloged file (e.g., add a comment to `.claude/hooks/git_commit_guard.py`). Stage and commit. Assert the manifest classification hook either does not fire or fires and reports "no uncatalogued files." Assert `tooling-manifest.json` has no duplicate `source` entries (use `jq '[.tools[].source] | group_by(.) | map(select(length > 1)) | length'` and assert result is 0). |

---

## AC7: Pluggable secrets

### AC7.1 — Azure Key Vault provider injects secrets into container

| Field | Value |
|---|---|
| **Test type** | Human verification |
| **Justification** | Requires an actual Azure Key Vault instance and authenticated `az` CLI session. Cannot be tested without Azure subscription credentials. |
| **Procedure** | 1. Ensure `az` CLI is authenticated (`az account show`). 2. Create or use an existing Key Vault with at least one secret. 3. Run `setup.sh` and select "Azure Key Vault" as the secrets provider. Enter the vault name. 4. Build and start the container. 5. Inside the container, confirm the secret is available: `cat /home/claude/.secrets.env` should contain `export SECRET_NAME=value`. 6. Run `echo $SECRET_NAME` and confirm the value matches the Key Vault secret. |

### AC7.2 — .env provider reads from user-specified path

| Field | Value |
|---|---|
| **Test type** | Script (automated) |
| **Test file** | `scripts/test-secrets.sh` |
| **Description** | Create a temp `.env` file with known key-value pairs (e.g., `TEST_KEY=test_value`). Source `config/secrets-env.sh` with the temp file path configured. Call `secrets_validate()` and assert exit 0. Call `secrets_inject()` and assert the output file contains `export TEST_KEY=test_value`. |

### AC7.3 — macOS Keychain provider reads via security CLI

| Field | Value |
|---|---|
| **Test type** | Human verification |
| **Justification** | macOS Keychain access via `security` CLI requires a logged-in macOS desktop session and may trigger system authentication prompts. Cannot run in CI. |
| **Procedure** | 1. Add a test secret to Keychain: `security add-generic-password -s "claude-env-test" -a "TEST_SECRET" -w "keychain_value"`. 2. Run `setup.sh` and select "macOS Keychain." Enter service name `claude-env-test`. 3. Confirm the host-side script reads the secret without error. 4. Build and start the container. 5. Inside the container, confirm `cat /home/claude/.secrets.env` contains `export TEST_SECRET=keychain_value`. 6. Clean up: `security delete-generic-password -s "claude-env-test" -a "TEST_SECRET"`. |

### AC7.4 — Skipping secrets during setup results in working container

| Field | Value |
|---|---|
| **Test type** | Script (automated) |
| **Test file** | `scripts/test-secrets.sh` |
| **Description** | Set `secrets.provider=none` in `.user-config.json`. Run `config/bootstrap-secrets.sh`. Assert exit code 0, assert output contains "No secrets provider configured", and assert no `.secrets.env` file is created (or it is empty). Build and start the container — assert it starts without errors. |

### AC7.5 — Selected provider persists across container rebuilds

| Field | Value |
|---|---|
| **Test type** | Script + Human verification |
| **Test file** | `scripts/test-secrets.sh` |
| **Automated portion** | Run `setup.sh` with a secrets provider selection. Assert `.user-config.json` contains the provider choice under `secrets.provider`. Simulate a container rebuild (delete container, rebuild image). Assert `.user-config.json` still contains the same provider choice (file is on the host, not in the container). |
| **Human verification** | After selecting a provider and building the container, run "Dev Containers: Rebuild Container" in VS Code. After rebuild, confirm secrets are still injected (check `/home/claude/.secrets.env`). |

---

## Test file summary

| File | Type | AC coverage |
|---|---|---|
| `scripts/validate.sh` | e2e validation | AC3.1-AC3.5, AC4.1-AC4.4, AC5.2, AC5.5 |
| `scripts/test-preflight.sh` | Preflight checks | AC1.1, AC1.4-AC1.7 |
| `scripts/test-identity-routing.sh` | Feature selection logic | AC2.1, AC2.2, AC2.5, AC2.6 |
| `scripts/test-distro-compat.sh` | Multi-distro Feature install | AC4.6 |
| `scripts/test-secrets.sh` | Secrets provider logic | AC7.2, AC7.4, AC7.5 |
| `scripts/test-manifest-hook.sh` | Manifest dedup check (claude-env repo) | AC6.4 |
| `.github/workflows/ci.yml` | CI pipeline | AC4.5 (build/lint), shellcheck for all .sh |
| `.github/workflows/publish-features.yml` | Feature publishing | AC4.5 |

## Human-only verification summary

The following criteria require human verification and cannot be fully automated:

| Criterion | Reason |
|---|---|
| AC1.2 | Docker Desktop install requires macOS GUI privilege prompts |
| AC1.3 | VS Code cask install requires macOS desktop environment |
| AC2.3 | UX quality of interactive prompt text |
| AC2.4 | UX quality of language grouping prompts |
| AC5.1 | VS Code reconnection is GUI-only |
| AC5.3 | Sleep/wake is hardware-dependent |
| AC5.4 | "Rebuild Container" is a VS Code UI command |
| AC6.1 | Classification agent requires active Claude Code + AI API |
| AC6.2 | Correctness of AI classification requires human judgment |
| AC6.3 | Diff display is a terminal UX behavior |
| AC7.1 | Requires live Azure Key Vault |
| AC7.3 | macOS Keychain requires desktop session |
