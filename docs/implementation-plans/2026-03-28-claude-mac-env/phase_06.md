# Claude Mac Environment Implementation Plan — Phase 6

**Goal:** Build the interactive prompts, identity routing, manifest-driven tiered selection, and devcontainer.json template generation in setup.sh.

**Architecture:** setup.sh continues after preflight (Phase 5) with interactive prompts. GitHub username drives identity routing: `psford` gets full install, others get tiered selection from tooling-manifest.json fetched from claude-env repo. A JSON template is rendered into the final devcontainer.json with selected Features, mounts, and extensions.

**Tech Stack:** Bash, jq (for JSON manipulation), curl (to fetch manifest from GitHub), heredoc templating

**Scope:** Phase 6 of 8 from original design

**Codebase verified:** 2026-03-29 — setup.sh exists with preflight checks from Phase 5. .devcontainer/devcontainer.json exists as hardcoded Phase 1 version. tooling-manifest.json exists in claude-env from Phase 4. All four Features exist from Phases 2-3.

---

## Acceptance Criteria Coverage

### claude-mac-env.AC2: Identity routing and tiered selection
- **claude-mac-env.AC2.1 Success:** GitHub username `psford` enables all Features without prompts
- **claude-mac-env.AC2.2 Success:** Other usernames see tiered selection from manifest
- **claude-mac-env.AC2.3 Success:** Universal tools presented with descriptions and y/n prompt
- **claude-mac-env.AC2.4 Success:** Language tools grouped by language with y/n per group
- **claude-mac-env.AC2.5 Success:** Personal tier never shown to non-psford users
- **claude-mac-env.AC2.6 Edge:** Empty manifest gracefully installs only claude-skills

### claude-mac-env.AC3: Container filesystem isolation (mount generation)
- **claude-mac-env.AC3.1 Success:** Project dirs writable from inside container
- **claude-mac-env.AC3.2 Success:** .gitconfig readable but not writable from container
- **claude-mac-env.AC3.3 Success:** .ssh readable but not writable from container
- **claude-mac-env.AC3.4 Success:** No other Mac paths visible inside container

### claude-mac-env.AC5: Day-to-day and rebuild workflow (config generation)
- **claude-mac-env.AC5.5 Success:** Destroying container + re-running setup.sh restores full env

---

<!-- START_TASK_1 -->
### Task 1: Add interactive prompts to setup.sh

**Files:**
- Modify: `setup.sh`

**Implementation:**

Add `collect_user_input()` function after preflight that prompts for:

1. **GitHub username**: `read -p "GitHub username: " GITHUB_USER`
   - Validate: non-empty, alphanumeric + hyphens
   - Store in config

2. **Project directories**: Allow multiple paths
   - Prompt: "Enter project directory paths (one per line, empty line to finish):"
   - Validate each path exists on the Mac filesystem
   - Default suggestion: `~/Projects` if it exists
   - Store as array in config

3. **Distro selection**: Present menu
   - 1) Ubuntu 24.04 (default)
   - 2) Debian 12
   - 3) Fedora 40
   - 4) Alpine (minimal)
   - 5) Custom (enter image name)
   - Map selection to Docker image name (e.g., `ubuntu:24.04`, `fedora:40`)
   - Store in config

4. **Config persistence**: Write selections to `.user-config.json` in the repo root. If file already exists, show previous values as defaults so re-running setup remembers choices.

```json
{
  "githubUser": "psford",
  "projectDirs": ["/Users/patrick/Projects", "/Users/patrick/repos"],
  "baseImage": "ubuntu:24.04",
  "features": {},
  "secrets": {}
}
```

**Verification:**

Run `bash setup.sh`, answer prompts. Verify `.user-config.json` is created with correct values. Re-run, verify previous values shown as defaults.

**Commit:** `feat: add interactive prompts and config persistence to setup.sh`
<!-- END_TASK_1 -->

<!-- START_TASK_2 -->
### Task 2: Add identity routing and manifest-driven tier selection

**Verifies:** claude-mac-env.AC2.1, claude-mac-env.AC2.2, claude-mac-env.AC2.3, claude-mac-env.AC2.4, claude-mac-env.AC2.5, claude-mac-env.AC2.6

**Files:**
- Modify: `setup.sh`

**Implementation:**

Add `select_features()` function that:

1. **Fetch manifest**: `curl -fsSL https://raw.githubusercontent.com/psford/claude-env/main/tooling-manifest.json`
   - If fetch fails: warn and fall back to claude-skills only (AC2.6)
   - Parse with `jq`

2. **If username is `psford`**: Enable all Features silently (AC2.1)
   ```bash
   SELECTED_FEATURES='{"claude-skills": {}, "universal-hooks": {}, "csharp-tools": {"dotnetVersion": "9.0"}, "psford-personal": {"installAzureCli": true}}'
   ```

3. **If any other username**: Tiered selection flow
   - **Always**: claude-skills (no prompt, always included)
   - **Universal tier** (AC2.3): Extract tools where `tier == "universal"` from manifest. Print summary:
     ```
     Universal development tools available:
       • Git branch protection — prevents direct push to main/master
       • Log sanitization — CWE-117 prevention
       • Commit atomicity — warns on large unfocused commits
       • ... (more from manifest descriptions)
     Install universal tools? (Y/n)
     ```
   - **Language tier** (AC2.4): Extract unique languages from manifest. For each language:
     ```
     C# / .NET tools available:
       • .NET SDK (configurable version)
       • Entity Framework migration hooks
     Install C# tools? (y/N)
     ```
     If yes, prompt for .NET version (default 9.0)
   - **Personal tier** (AC2.5): Skip entirely. Never shown, never offered.

4. Build `SELECTED_FEATURES` JSON object based on selections.

5. Store selections in `.user-config.json` under `features` key.

**Verification:**

Run setup.sh as `psford`: all Features selected without prompts.
Run setup.sh with any other username: tiered selection prompts appear.
Delete manifest from GitHub (simulate): falls back to claude-skills only.

**Commit:** `feat: add identity routing and tiered feature selection`
<!-- END_TASK_2 -->

<!-- START_TASK_3 -->
### Task 3: Create devcontainer.json template and rendering

**Verifies:** claude-mac-env.AC3.1, claude-mac-env.AC3.2, claude-mac-env.AC3.3, claude-mac-env.AC3.4

**Files:**
- Create: `.devcontainer/devcontainer.json.template`
- Modify: `setup.sh` (add template rendering)

**Implementation:**

Template file with placeholders:
```
{
  "name": "Claude Dev Environment",
  "build": {
    "dockerfile": "../Dockerfile",
    "context": "..",
    "args": {
      "BASE_IMAGE": "{{BASE_IMAGE}}"
    }
  },
  "remoteUser": "claude",
  "features": {{FEATURES}},
  "mounts": [
    {{PROJECT_MOUNTS}}
    "source=${localEnv:HOME}/.gitconfig,target=/home/claude/.gitconfig,type=bind,readonly",
    "source=${localEnv:HOME}/.ssh,target=/home/claude/.ssh,type=bind,readonly"
  ],
  "workspaceFolder": "/workspaces",
  "customizations": {
    "vscode": {
      "extensions": [
        "anthropics.claude-code"
        {{EXTRA_EXTENSIONS}}
      ]
    }
  },
  "postCreateCommand": "bash /workspaces/.claude-mac-env/config/bootstrap-secrets.sh || true"
}
```

Add `render_devcontainer()` function to setup.sh:
1. Read template
2. Replace `{{BASE_IMAGE}}` with selected distro image
3. Replace `{{FEATURES}}` with GHCR-referenced features JSON (using published URLs, not local paths):
   ```json
   {
     "ghcr.io/psford/claude-mac-env/claude-skills:latest": {},
     "ghcr.io/psford/claude-mac-env/universal-hooks:latest": {}
   }
   ```
4. Replace `{{PROJECT_MOUNTS}}` with bind mount entries for each project dir:
   ```
   "source=/Users/patrick/Projects,target=/workspaces/Projects,type=bind",
   ```
   Each project dir gets its own mount under `/workspaces/`
5. Replace `{{EXTRA_EXTENSIONS}}` with language-specific extensions if applicable (e.g., `ms-dotnettools.csharp` for C# tools)
6. Write rendered output to `.devcontainer/devcontainer.json`
7. Update `.gitignore` to uncomment the `devcontainer.json` entry (it was commented out in Phase 1 since Phase 1 committed it directly; now it's generated per-user and should be ignored)

**Verification:**

Run setup.sh through config generation. Inspect `.devcontainer/devcontainer.json`:
- Correct base image
- Correct Features (GHCR URLs)
- Project dirs mounted read-write
- Dotfiles mounted read-only
- No unexpected mounts

**Commit:** `feat: add devcontainer.json template and rendering`
<!-- END_TASK_3 -->

<!-- START_TASK_4 -->
### Task 4: Wire up end-to-end setup flow with docker build

**Verifies:** claude-mac-env.AC5.5

**Files:**
- Modify: `setup.sh`

**Implementation:**

Add `build_and_launch()` function as the final step of setup.sh:

1. Build base Docker image: `docker build --build-arg BASE_IMAGE="${BASE_IMAGE}" -t claude-mac-env:latest .`
2. Print success message with next steps:
   ```
   ✓ Setup complete!

   To start your environment:
     1. Open VS Code: code /path/to/claude-mac-env
     2. When prompted, click "Reopen in Container"
     3. Wait for the container to build (first time only)

   Day-to-day: just open VS Code — it reconnects automatically.

   To rebuild from scratch:
     docker rm -f <container>
     docker rmi claude-mac-env:latest
     ./setup.sh
   ```

Wire the complete flow in `main()`:
```bash
main() {
  run_preflight
  collect_user_input
  select_features
  render_devcontainer
  build_and_launch
}
```

Handle `--preflight-only` flag (from Phase 5) to exit early.

**Verification:**

Run: `shellcheck setup.sh`
Expected: No errors

Full end-to-end run: `./setup.sh` from fresh state → all prompts → config generated → image built → open in VS Code → container works.

Re-run `./setup.sh` → shows previous config as defaults → generates new config → rebuilds.

**Commit:** `feat: wire end-to-end setup flow with docker build`
<!-- END_TASK_4 -->
