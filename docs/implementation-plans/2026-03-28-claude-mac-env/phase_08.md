# Claude Mac Environment Implementation Plan — Phase 8

**Goal:** Documentation for users and contributors, end-to-end validation script, CI pipeline, and tagged v1.0 release.

**Architecture:** README as primary user-facing doc, CONTRIBUTING.md for maintainers, GitHub Actions for CI (image build, Feature publish, shellcheck linting), e2e validation script for smoke testing.

**Tech Stack:** Markdown, GitHub Actions, ShellCheck, gh CLI for release

**Scope:** Phase 8 of 8 from original design

**Codebase verified:** 2026-03-29 — All prior phases complete. Full setup.sh, Dockerfile, 4 Features, manifest, secrets framework all in place.

---

## Acceptance Criteria Coverage

### claude-mac-env.AC5: Day-to-day and rebuild workflow (remaining items)
- **claude-mac-env.AC5.1 Success:** VS Code reconnects to existing container without rebuild
- **claude-mac-env.AC5.3 Success:** Container survives Mac sleep/wake cycle
- **claude-mac-env.AC5.4 Success:** 'Rebuild Container' reinstalls Features from GHCR
- **claude-mac-env.AC5.5 Success:** Destroying container + re-running setup.sh restores full env

Note: AC5.1, AC5.3, AC5.4 are verified through documentation of expected behavior and manual testing. AC5.5 is verified by the e2e validation script.

---

<!-- START_TASK_1 -->
### Task 1: Create README.md

**Files:**
- Create: `README.md`

**Implementation:**

Structure:
1. **Title and one-line description**: "Containerized Claude Code development environment for Apple Silicon Macs"
2. **What this does**: 2-3 sentences explaining the value prop (Claude Code in a sandboxed container, read-only Mac access, shareable bootstrap)
3. **Prerequisites**: Apple Silicon Mac. That's it — setup.sh handles the rest.
4. **Quickstart**: Clone, run `./setup.sh`, open in VS Code. Three steps.
5. **What gets installed**: Table showing what setup.sh installs (Homebrew, Docker, VS Code, etc.) with note that each asks permission first
6. **Day-to-day usage**: Open VS Code → auto-reconnects. Green indicator means you're in the container. Claude Code available in terminal.
7. **Filesystem access**: Table showing what's mounted and how (project RW, dotfiles RO, everything else invisible)
8. **Customizing tooling**: Explain the tiered system (universal, language, personal), how to change selections by re-running setup.sh
9. **Nuke and pave**: How to destroy everything and rebuild (`docker rm`, `docker rmi`, re-run setup.sh)
10. **Sharing**: How to share this with someone else — they clone, run setup.sh, enter their GitHub username
11. **Secrets management**: Brief overview of the three providers, how to select one
12. **Troubleshooting**: Common issues from install-notes.md, formatted as FAQ

Keep it concise. Link to CONTRIBUTING.md for technical details.

**Verification:**

Review README renders correctly on GitHub (push and check, or use local markdown preview).

**Commit:** `docs: add README with quickstart and usage guide`
<!-- END_TASK_1 -->

<!-- START_TASK_2 -->
### Task 2: Create CONTRIBUTING.md

**Files:**
- Create: `CONTRIBUTING.md`

**Implementation:**

Structure:
1. **Adding a new Dev Container Feature**: File structure, devcontainer-feature.json schema, install.sh requirements, how to test locally, how publishing works via CI
2. **Tooling manifest**: Schema explanation, how to add entries, how the classification hook works
3. **Modifying setup.sh**: Function structure, how preflight checks work, how to add a new dependency check
4. **Secrets providers**: How to add a new provider (implement the interface, add to setup.sh menu)
5. **Testing**: How to run the e2e validation script, what it checks
6. **Release process**: How to tag a release, what CI does on release

**Verification:**

Review renders correctly, links to relevant files work.

**Commit:** `docs: add CONTRIBUTING guide for maintainers`
<!-- END_TASK_2 -->

<!-- START_TASK_3 -->
### Task 3: Create e2e validation script

**Files:**
- Create: `scripts/validate.sh`

**Implementation:**

Script that validates the full environment works. Designed to run after setup.sh completes. Checks:

1. Docker image builds successfully (`docker build -t claude-mac-env:test .`)
2. Container starts (`docker run --rm claude-mac-env:test echo "OK"`)
3. Claude Code is installed (`docker run --rm claude-mac-env:test claude --version`)
4. Non-root user is correct (`docker run --rm claude-mac-env:test whoami` → `claude`)
5. Node.js version is LTS (`docker run --rm claude-mac-env:test node --version`)
6. Python is available (`docker run --rm claude-mac-env:test python3 --version`)
7. detect-package-manager.sh works (`docker run --rm claude-mac-env:test detect-package-manager.sh` → `apt`)
8. Bind mount simulation: create temp dir, mount RW, verify write works
9. Read-only mount simulation: mount file RO, verify write fails
10. Feature installation: use `devcontainer build --workspace-folder .` (if devcontainers CLI available) or verify Feature artifacts exist in the built image by checking `~/.claude/hooks/` and `~/.claude/skills/` directories

Print results as pass/fail checklist. Exit 0 if all pass, exit 1 on any failure.

**Verification:**

Run: `bash scripts/validate.sh`
Expected: All checks pass on a working environment

**Commit:** `feat: add e2e validation script`
<!-- END_TASK_3 -->

<!-- START_TASK_4 -->
### Task 4: Create GitHub Actions CI workflow

**Files:**
- Create: `.github/workflows/ci.yml`

**Implementation:**

Workflow triggers on push to main and pull requests. Jobs:

1. **lint**: Run ShellCheck on all .sh files (`shellcheck setup.sh config/*.sh scripts/*.sh detect-package-manager.sh`)
2. **build**: Build Docker image on `ubuntu-latest` (verifies Dockerfile works on amd64 — arm64 testing requires self-hosted runner or manual verification)
3. **validate**: Run `scripts/validate.sh` against the built image

Feature publishing is a separate workflow (created in Phase 2) that triggers on tags.

```yaml
name: CI
on:
  push:
    branches: [main]
  pull_request:
    branches: [main]

jobs:
  lint:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - name: Install ShellCheck
        run: sudo apt-get install -y shellcheck
      - name: Lint shell scripts
        run: shellcheck setup.sh config/*.sh scripts/*.sh detect-package-manager.sh

  build:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - name: Build Docker image
        run: docker build -t claude-mac-env:ci .

  validate:
    needs: build
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - name: Build and validate
        run: |
          docker build -t claude-mac-env:ci .
          bash scripts/validate.sh
```

**Verification:**

Push to main → CI runs → all jobs pass

**Commit:** `ci: add GitHub Actions workflow for lint, build, validate`
<!-- END_TASK_4 -->

<!-- START_TASK_5 -->
### Task 5: Tag v1.0 release

**Files:**
- None (git tag + gh release)

**Implementation:**

1. Ensure all CI checks pass on main
2. Create annotated tag: `git tag -a v1.0.0 -m "Initial release: containerized Claude Code dev environment for Apple Silicon Macs"`
3. Push tag: `git push origin v1.0.0`
4. Create GitHub release: `gh release create v1.0.0 --title "v1.0.0 — Initial Release" --notes "..."` with release notes summarizing features:
   - Containerized Claude Code on Apple Silicon Macs
   - Single setup.sh bootstrap script
   - Dev Container Features for modular tooling
   - Tiered tool selection based on identity
   - Pluggable secrets management
   - CLI-first dependency installation

**Verification:**

Visit https://github.com/psford/claude-mac-env/releases → v1.0.0 release visible with notes

**Commit:** No commit needed — tag and release only.
<!-- END_TASK_5 -->
