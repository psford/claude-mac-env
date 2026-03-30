# Retrospective Log

Items logged during development for post-deployment review.
Each entry captures friction, dead ends, rewrites, and lessons learned.

---

### 2026-03-29 [REPEATED-FAILURE] Per-phase code reviews missed cross-phase integration issues
- **Context**: Executing 8-phase implementation plan for claude-mac-env
- **What happened**: Per-phase reviews caught issues within each phase (67 total issues across 8 phases), but the final review found 3 additional criticals: Dockerfile only supports apt but setup.sh offers Fedora/Alpine, secrets-env.sh double-quotes already-quoted values, __pycache__ tracked in git.
- **Impact**: 3 critical issues discovered at the end instead of during implementation. Extra review-fix cycle.
- **Resolution**: Fixed all 3, but the process failed to catch cross-phase contradictions. Need cross-phase sanity checks during execution, not just at the end.

### 2026-03-29 [ASSUMPTION] Dev Container Features can reference paths outside .devcontainer/
- **Context**: devcontainer.json referenced features at `./features/claude-skills` then `../features/claude-skills`
- **What happened**: Dev Containers CLI requires local features to be children of `.devcontainer/` directory. Both `./features/` and `../features/` were rejected. Tried 3 paths before discovering the constraint.
- **Impact**: Container failed to start 3 times. Had to strip features entirely to get a working container.
- **Resolution**: Features must either live under `.devcontainer/features/` or be published to GHCR. Neither was done. Deferred to post-MVP.

### 2026-03-29 [ASSUMPTION] Homebrew `docker` cask is current
- **Context**: setup.sh used `brew install --cask docker`
- **What happened**: Cask was renamed to `docker-desktop`. The old name either doesn't exist or pulls a different package.
- **Impact**: Docker install failed on first attempt.
- **Resolution**: Changed to `brew install --cask docker-desktop`.

### 2026-03-29 [ASSUMPTION] `--no-quarantine` flag still exists in Homebrew
- **Context**: setup.sh used `brew install --cask docker --no-quarantine`
- **What happened**: Flag was removed in a recent Homebrew update. Install fails with "switch is disabled."
- **Impact**: Docker and VS Code installs both failed on first attempt.
- **Resolution**: Removed `--no-quarantine` from all brew cask commands.

### 2026-03-29 [ROOT-CAUSE] Intel Homebrew on Apple Silicon downloads wrong-arch packages
- **Context**: User had Homebrew installed at `/usr/local/bin/brew` (Intel/Rosetta path)
- **What happened**: setup.sh found brew in PATH and used it. Intel brew downloaded Intel Docker Desktop, which shows "This is the Intel version" error on launch.
- **Impact**: Docker install succeeded but Docker itself was unusable. Multiple debug cycles.
- **Resolution**: Added detection: if brew is at `/usr/local/` on an arm64 Mac, auto-install ARM brew at `/opt/homebrew/`. Also persist brew to shell profile.

### 2026-03-29 [ROOT-CAUSE] Ubuntu 24.04 ships with existing UID/GID 1000
- **Context**: Dockerfile creates user `claude` with UID/GID 1000
- **What happened**: `groupadd --gid 1000` fails because Ubuntu 24.04 has a default `ubuntu` user at that ID. First fix (`|| true`) silently skipped user creation, then `chown claude:claude` failed because user didn't exist.
- **Impact**: Docker build failed twice. First fix introduced a second failure.
- **Resolution**: Delete the `ubuntu` user/group first with `userdel -r ubuntu`, then create `claude`.

### 2026-03-29 [REPEATED-FAILURE] Template rendering produces invalid JSON
- **Context**: setup.sh renders devcontainer.json from a template using bash string replacement
- **What happened**: Missing comma between secrets mounts and dotfile mounts. Previously also had trailing comma issue with extensions array. Bash string replacement for JSON is fundamentally fragile.
- **Impact**: Container failed to start due to JSON parse error. Multiple comma-related bugs across the session.
- **Resolution**: Fixed the specific comma bug, but the root cause (bash string replacement for JSON) remains. Should use jq for JSON generation.

### 2026-03-29 [WASTED-TIME] 500+ permission prompts during plan execution
- **Context**: Executing 8-phase plan with subagents making edits
- **What happened**: Every tool call (file read, edit, bash command) triggered a permission approval prompt. Sequential single-line edits to the same file each required separate approval. User could not leave the computer.
- **Impact**: User described it as "the most frustrating experience I've had on a computer in years." Hours of babysitting approvals.
- **Resolution**: No code fix — this is a Claude Code permission model issue. The container environment (claude-mac-env) is literally being built to solve this by running with `--dangerously-skip-permissions` inside the sandbox.

### 2026-03-29 [ASSUMPTION] GHCR features would be available for local testing
- **Context**: Template rendering generates GHCR URLs like `ghcr.io/psford/claude-mac-env/claude-skills:latest`
- **What happened**: Features were never published to GHCR. The publish workflow exists but was never triggered. Generated devcontainer.json references packages that don't exist.
- **Impact**: Container couldn't resolve features. Had to strip them to get a working container.
- **Resolution**: Deferred. Must publish features before they can be referenced by GHCR URL.

### 2026-03-29 [TOOL-LIMIT] `code` CLI not in PATH after VS Code install
- **Context**: Setup complete message tells user to run `code /path/to/project`
- **What happened**: VS Code was installed via brew cask but the `code` CLI command wasn't linked to PATH. User got "command not found."
- **Impact**: User couldn't follow the setup instructions. Had to manually open VS Code via Finder with Cmd+Shift+G to navigate hidden paths.
- **Resolution**: Deferred. Need to either run VS Code's "Install code command" or symlink manually in setup.sh.

### 2026-03-29 [ASSUMPTION] Test files specified in test-requirements.md would be created during implementation
- **Context**: test-requirements.md specified 6 test scripts. Implementation phases didn't include tasks to create them.
- **What happened**: 4 of 6 required test files were missing after all 8 phases completed. Created retroactively at the end with weaker coverage than TDD would have produced.
- **Impact**: Test coverage gaps. Tests written after code don't catch the same bugs as tests written before.
- **Resolution**: Created the files retroactively. Process fix: cross-reference test-requirements.md during phase execution, not just at final review.

### 2026-03-29 [ASSUMPTION] Docker build cache is helpful during iterative Dockerfile changes
- **Context**: Dockerfile was modified to fix UID/GID issue, but docker build used cached layers
- **What happened**: `docker build` kept using the cached (broken) layer. User saw the same error after the fix was applied.
- **Impact**: Confusion — "I fixed it, why is it still broken?" Extra debug cycle.
- **Resolution**: Added `--no-cache` to docker build in setup.sh. But this is wasteful for rebuilds where the Dockerfile hasn't changed. Need smarter cache invalidation.
