# Human Test Plan — claude-mac-env

Generated after implementation of all 8 phases. Covers acceptance criteria that require manual verification on Apple Silicon Mac hardware with GUI access.

## Prerequisites

- Apple Silicon Mac (M1/M2/M3/M4)
- macOS with admin access
- GitHub account with push access to psford/claude-mac-env
- Azure subscription (for AC7.1 only)

## Manual Test Procedures

### 1. Docker Desktop Installation (AC1.2)

| Step | Action | Expected Result |
|------|--------|-----------------|
| 1 | Uninstall Docker: `brew uninstall --cask docker` | Docker removed |
| 2 | Run `./setup.sh --preflight-only` | Script explains Docker Desktop and asks permission |
| 3 | Answer "y" | `brew install --cask docker` runs |
| 4 | Wait for daemon prompt | Script waits for Docker daemon (up to 60s) |
| 5 | Authorize Docker Desktop if prompted | First-launch privilege grant |
| 6 | Verify | `docker info` succeeds, script shows Docker version in summary |

### 2. VS Code Installation (AC1.3)

| Step | Action | Expected Result |
|------|--------|-----------------|
| 1 | Uninstall VS Code: `brew uninstall --cask visual-studio-code` | VS Code removed |
| 2 | Run `./setup.sh --preflight-only` | Script asks permission for VS Code |
| 3 | Answer "y" | `brew install --cask visual-studio-code` runs |
| 4 | Verify | `code --version` succeeds |

### 3. VS Code Decline (AC1.7)

| Step | Action | Expected Result |
|------|--------|-----------------|
| 1 | Ensure VS Code is not installed | |
| 2 | Run `./setup.sh --preflight-only` | Script asks about VS Code |
| 3 | Answer "n" | Script prints "Skipping VS Code" and continues |
| 4 | Verify | Script completes with exit 0, summary shows "VS Code: skipped" |

### 4. Interactive Prompt UX (AC2.3, AC2.4)

| Step | Action | Expected Result |
|------|--------|-----------------|
| 1 | Run `./setup.sh` with a non-psford username | |
| 2 | Observe universal tier prompt | Lists tools with one-line descriptions, single y/n prompt |
| 3 | Answer "y" | universal-hooks added to config |
| 4 | Observe language tier prompt | C# tools grouped separately, own y/n prompt |
| 5 | Answer "y" for C# | Prompts for .NET version (default 9.0) |
| 6 | Check generated devcontainer.json | Contains selected features with GHCR URLs |

### 5. Full End-to-End Setup (AC5.5)

| Step | Action | Expected Result |
|------|--------|-----------------|
| 1 | Run `./setup.sh` from fresh state | All prompts, config generated, image built |
| 2 | Open VS Code: `code .` | "Reopen in Container" notification appears |
| 3 | Click "Reopen in Container" | Container builds, VS Code connects (green indicator) |
| 4 | In container terminal: `claude --version` | Claude Code version printed |
| 5 | In container terminal: `whoami` | `claude` (not root) |
| 6 | In container terminal: `touch /workspaces/test && rm /workspaces/test` | Succeeds (RW mount) |
| 7 | In container terminal: `echo x >> ~/.gitconfig` | Fails (RO mount) |

### 6. VS Code Reconnection (AC5.1)

| Step | Action | Expected Result |
|------|--------|-----------------|
| 1 | With container running, close VS Code (Cmd+Q) | |
| 2 | Reopen VS Code, open same project | Green indicator reappears within seconds |
| 3 | Open terminal, run `uptime` | Container has been running since original build |

### 7. Sleep/Wake Survival (AC5.3)

| Step | Action | Expected Result |
|------|--------|-----------------|
| 1 | With container running, close laptop lid | Mac sleeps |
| 2 | Wait 30+ seconds | |
| 3 | Open lid, switch to VS Code | |
| 4 | Run `date` in terminal | Terminal responds, container alive |
| 5 | Run `claude --version` | Still works |

### 8. Rebuild Container (AC5.4)

| Step | Action | Expected Result |
|------|--------|-----------------|
| 1 | Cmd+Shift+P > "Dev Containers: Rebuild Container" | Rebuild starts |
| 2 | Watch build log | GHCR Feature URLs appear in log |
| 3 | After rebuild: `claude --version` | Works |
| 4 | After rebuild: check hooks directory | Hooks present |

### 9. Nuke and Pave (AC5.5)

| Step | Action | Expected Result |
|------|--------|-----------------|
| 1 | `docker rm -f $(docker ps -aq --filter ancestor=claude-mac-env)` | Container removed |
| 2 | `docker rmi claude-mac-env:latest` | Image removed |
| 3 | `./setup.sh` (answers restored from .user-config.json) | Rebuilds everything |
| 4 | Open in VS Code, verify full environment | All tools, hooks, secrets work |

### 10. Classification Hook (AC6.1-AC6.3)

| Step | Action | Expected Result |
|------|--------|-----------------|
| 1 | In claude-env repo, create `helpers/test_new_helper.py` | |
| 2 | `git add helpers/test_new_helper.py` | |
| 3 | Initiate commit in Claude Code | Classification hook fires |
| 4 | Inspect proposed manifest entry | Has tier, language, feature, description |
| 5 | Verify diff is shown | tooling-manifest.json changes displayed |
| 6 | Clean up: remove test file, revert manifest | |

### 11. Azure Key Vault Secrets (AC7.1)

| Step | Action | Expected Result |
|------|--------|-----------------|
| 1 | Ensure `az account show` works | Authenticated |
| 2 | Run `./setup.sh`, select "Azure Key Vault" | Prompts for vault name |
| 3 | Enter vault name with at least one secret | |
| 4 | Build and start container | |
| 5 | `cat /home/claude/.secrets.env` | Contains `export SECRET_NAME="value"` |

### 12. macOS Keychain Secrets (AC7.3)

| Step | Action | Expected Result |
|------|--------|-----------------|
| 1 | `security add-generic-password -s "claude-env-test" -a "TEST_KEY" -w "test_value"` | Secret added |
| 2 | Run `./setup.sh`, select "macOS Keychain" | Prompts for service name |
| 3 | Enter `claude-env-test`, account name `TEST_KEY` | |
| 4 | Build and start container | |
| 5 | `cat /home/claude/.secrets.env` | Contains `export TEST_KEY="test_value"` |
| 6 | Clean up: `security delete-generic-password -s "claude-env-test" -a "TEST_KEY"` | |

### 13. Feature Publishing (AC4.5)

| Step | Action | Expected Result |
|------|--------|-----------------|
| 1 | `git tag v1.0.0 && git push origin v1.0.0` | Tag pushed |
| 2 | Check GitHub Actions | publish-features workflow runs |
| 3 | After completion, check GHCR | 4 Feature packages visible |
| 4 | Set packages to public visibility | |

---

## Results Tracking

| Test | AC | Pass/Fail | Date | Tester | Notes |
|------|-----|-----------|------|--------|-------|
| Docker install | AC1.2 | | | | |
| VS Code install | AC1.3 | | | | |
| VS Code decline | AC1.7 | | | | |
| Prompt UX | AC2.3/AC2.4 | | | | |
| Full E2E | AC5.5 | | | | |
| Reconnection | AC5.1 | | | | |
| Sleep/wake | AC5.3 | | | | |
| Rebuild | AC5.4 | | | | |
| Nuke/pave | AC5.5 | | | | |
| Classification | AC6.1-AC6.3 | | | | |
| Azure secrets | AC7.1 | | | | |
| Keychain secrets | AC7.3 | | | | |
| Feature publish | AC4.5 | | | | |
