# Claude Mac Environment Implementation Plan — Phase 2

**Goal:** Package the `claude-skills` and `universal-hooks` tooling tiers as Dev Container Features and set up the GitHub Actions workflow for publishing them to GHCR.

**Architecture:** Each Feature follows the Dev Container Features spec: `devcontainer-feature.json` metadata + `install.sh` installer. Features are published as OCI artifacts to GHCR via GitHub Actions using the `devcontainers/action` workflow. During development, features are referenced locally from the repo.

**Tech Stack:** Dev Container Features spec, GitHub Actions, GHCR (ghcr.io), OCI artifacts, bash

**Scope:** Phase 2 of 8 from original design

**Codebase verified:** 2026-03-29 — Dockerfile exists from Phase 1. No features/ directory exists yet. No GitHub Actions workflows exist yet. claude-env repo at github.com/psford/claude-env contains hooks in `.claude/hooks/` and helpers in `helpers/`.

---

## Acceptance Criteria Coverage

### claude-mac-env.AC4: Dev Container Features (partial)
- **claude-mac-env.AC4.1 Success:** claude-skills Feature installs and skills are usable
- **claude-mac-env.AC4.2 Success:** universal-hooks Feature installs and hooks trigger on git ops
- **claude-mac-env.AC4.5 Success:** Features publish to GHCR via GitHub Actions

---

<!-- START_SUBCOMPONENT_A (tasks 1-2) -->
<!-- START_TASK_1 -->
### Task 1: Create claude-skills Feature

**Files:**
- Create: `features/claude-skills/devcontainer-feature.json`
- Create: `features/claude-skills/install.sh`

**Implementation:**

`devcontainer-feature.json`:
```json
{
  "id": "claude-skills",
  "version": "1.0.0",
  "name": "Claude Code Skills",
  "description": "Installs ed3d plugin skills and psford custom skills for Claude Code",
  "options": {},
  "installsAfter": []
}
```

`install.sh`:
- Runs as root during Feature installation
- Installs Claude Code skills/plugins:
  1. Check if `claude` CLI is available (should be from base image)
  2. Clone or download ed3d plugin skills from their source repository
  3. Clone or download psford custom skills from claude-env repo
  4. Install skills to the appropriate Claude Code skills directory
     - Claude Code skills are typically installed to `~/.claude/skills/` or managed via the CLI
     - Use `claude skill install` if available, or copy skill directories directly
  5. Verify skills are listed: `claude skill list` (or equivalent check)

**Pre-implementation investigation required:** Before writing install.sh, the implementor must determine the exact Claude Code skill installation mechanism by running `claude --help` inside the base container from Phase 1 and checking for skill/plugin management commands. As of research date, skills are installed by copying directories to `~/.claude/skills/<skill-name>/` with a `SKILL.md` file. Plugins can be installed via `/plugin install` in Claude Code. The implementor should verify this and use concrete commands — do not ship an install.sh with conditional "if available" logic.

**Verification:**

Build container with feature referenced locally in devcontainer.json:
```json
"features": {
  "./features/claude-skills": {}
}
```
Open container, run `claude` and verify skills are available.

**Commit:** `feat: add claude-skills Dev Container Feature`
<!-- END_TASK_1 -->

<!-- START_TASK_2 -->
### Task 2: Create universal-hooks Feature

**Files:**
- Create: `features/universal-hooks/devcontainer-feature.json`
- Create: `features/universal-hooks/install.sh`
- Create: `features/universal-hooks/hooks/` (directory with hook scripts)

**Implementation:**

`devcontainer-feature.json`:
```json
{
  "id": "universal-hooks",
  "version": "1.0.0",
  "name": "Universal Git & Claude Hooks",
  "description": "Branch protection, log sanitization, commit atomicity, documentation, and commit permission hooks",
  "options": {},
  "installsAfter": ["ghcr.io/psford/claude-mac-env/claude-skills"]
}
```

`install.sh`:
- Runs as root during Feature installation
- Installs hooks to a global git hooks directory or as git template hooks:
  1. Create `/usr/local/share/claude-hooks/` directory
  2. Copy hook scripts from the bundled `hooks/` directory
  3. Configure git to use global hooks: `git config --system core.hooksPath /usr/local/share/claude-hooks/`
  4. Alternatively, install as Claude Code hooks to `~/.claude/hooks/` (per claude-env pattern)

Hook scripts to include (sourced from claude-env `.claude/hooks/`):

- **pre-push-branch-guard.sh**: Prevents direct push to main/master branches. Prompts user to confirm if pushing to protected branch.
- **pre-commit-log-sanitize.sh**: Checks staged files for CWE-117 log injection patterns. Warns on suspicious log statements.
- **pre-commit-atomicity.sh**: Validates commit atomicity — warns if commit touches too many unrelated files.
- **prepare-commit-msg-docs.sh**: Reminds to update documentation when modifying public APIs or exported functions.
- **pre-commit-permission.sh**: Asks for explicit confirmation before committing (Claude Code commit discipline).

Each hook script must:
- Be distro-agnostic (pure bash/git, no package manager calls)
- Exit 0 on success, non-zero to block the operation
- Include a `--no-verify` bypass note in error messages

**Verification:**

Build container with both features. Inside container:
```bash
cd /workspaces
git init test-repo && cd test-repo
git checkout -b test-branch
echo "test" > file.txt && git add file.txt
git commit -m "test"  # Should trigger hooks
```

**Commit:** `feat: add universal-hooks Dev Container Feature`
<!-- END_TASK_2 -->
<!-- END_SUBCOMPONENT_A -->

<!-- START_TASK_3 -->
### Task 3: Create GitHub Actions Feature publishing workflow

**Verifies:** claude-mac-env.AC4.5

**Files:**
- Create: `.github/workflows/publish-features.yml`

**Implementation:**

Workflow that publishes all Features to GHCR when a tag is pushed:

```yaml
name: Publish Dev Container Features
on:
  push:
    tags:
      - 'v*'
  workflow_dispatch:

jobs:
  publish:
    runs-on: ubuntu-latest
    permissions:
      contents: read
      packages: write
    steps:
      - uses: actions/checkout@v4

      - name: Login to GHCR
        uses: docker/login-action@v3
        with:
          registry: ghcr.io
          username: ${{ github.actor }}
          password: ${{ secrets.GITHUB_TOKEN }}

      - name: Publish Features
        uses: devcontainers/action@v1
        with:
          publish-features: true
          base-path-to-features: ./features
```

After publishing, Features are available at:
- `ghcr.io/psford/claude-mac-env/claude-skills:latest`
- `ghcr.io/psford/claude-mac-env/universal-hooks:latest`

Note: GHCR packages default to private. After first publish, go to GitHub → Packages → each Feature → Settings → Change visibility to Public.

**Verification:**

Push a tag (`git tag v0.1.0 && git push origin v0.1.0`) → GitHub Actions runs → Features appear in GHCR.

**Commit:** `ci: add GitHub Actions workflow for publishing Dev Container Features`
<!-- END_TASK_3 -->

<!-- START_TASK_4 -->
### Task 4: Update devcontainer.json to use local Features

**Files:**
- Modify: `.devcontainer/devcontainer.json`

**Implementation:**

Update the Phase 1 devcontainer.json to reference the local Features for development:

```json
{
  "name": "Claude Dev Environment",
  "build": {
    "dockerfile": "../Dockerfile",
    "context": ".."
  },
  "remoteUser": "claude",
  "features": {
    "./features/claude-skills": {},
    "./features/universal-hooks": {}
  },
  "mounts": [
    "source=${localEnv:HOME}/.gitconfig,target=/home/claude/.gitconfig,type=bind,readonly",
    "source=${localEnv:HOME}/.ssh,target=/home/claude/.ssh,type=bind,readonly"
  ],
  "workspaceFolder": "/workspaces",
  "workspaceMount": "source=${localWorkspaceFolder},target=/workspaces,type=bind",
  "customizations": {
    "vscode": {
      "extensions": [
        "anthropics.claude-code"
      ]
    }
  },
  "postCreateCommand": "echo 'Claude Dev Environment ready. Claude Code version:' && claude --version"
}
```

Note: Local feature references (`./features/...`) are used during development. The published GHCR references (`ghcr.io/psford/...`) will be used in the template generated by setup.sh (Phase 6).

**Verification:**

Rebuild container in VS Code (`Dev Containers: Rebuild Container`). Both Features should install. Verify skills are present and hooks trigger on git operations.

**Commit:** `feat: update devcontainer.json to use local Features`
<!-- END_TASK_4 -->
