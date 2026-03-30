# Bootstrap v2 Implementation Plan — Phase 1

**Goal:** Strip auth-dependent commands from `claude-skills` Feature install.sh so all 4 Features are publishable, then add post-publish verification to the workflow.

**Architecture:** Dev Container Features run at Docker image build time with no auth, no user session, no mounted volumes. The `claude-skills` Feature currently violates this by requiring `gh auth status` and cloning private repos. This phase removes those violations, reducing `install.sh` to directory creation + ownership fixup only. Skills installation moves to `config/bootstrap.sh` in Phase 4.

**Tech Stack:** Bash, GitHub Actions, `devcontainers/action@v1`, `docker manifest inspect`

**Scope:** Phase 1 of 7 from original design

**Codebase verified:** 2026-03-30

---

## Acceptance Criteria Coverage

This phase implements and tests:

### bootstrap-v2.AC1: Features published to GHCR
- **bootstrap-v2.AC1.1 Success:** All 4 Features resolve via `docker manifest inspect ghcr.io/psford/claude-mac-env/<feature>:1.0.0`
- **bootstrap-v2.AC1.2 Success:** Dev Containers CLI can pull and install each Feature during container build
- **bootstrap-v2.AC1.3 Failure:** Publish workflow fails if Feature install.sh contains `gh auth`, `az login`, or private repo clone
- **bootstrap-v2.AC1.4 Edge:** Re-publishing same tag overwrites existing OCI image (idempotent)

---

<!-- START_TASK_1 -->
### Task 1: Strip auth and clone logic from claude-skills/install.sh

**Files:**
- Modify: `features/claude-skills/install.sh` (rewrite lines 1-113)

**Step 1: Rewrite install.sh**

Replace the entire contents of `features/claude-skills/install.sh` with:

```bash
#!/bin/bash
set -e

# claude-skills Feature: Prepare skills directory structure
#
# This Feature runs at Docker image build time where NO auth, NO user session,
# and NO mounted volumes are available. It ONLY creates the directory structure
# and sets ownership. Actual skill installation happens in config/bootstrap.sh
# at container start time (postCreateCommand) where auth is available.

# Use the remote user's home directory for skills installation
SKILLS_DIR="${_REMOTE_USER_HOME}/.claude/skills"

echo "Preparing Claude Code Skills directory..."

# Create skills directory structure
mkdir -p "${SKILLS_DIR}"
echo "Created skills directory: ${SKILLS_DIR}"

# Set proper ownership of the skills directory for the remote user
if [ -n "${_REMOTE_USER}" ]; then
    chown -R "${_REMOTE_USER}:${_REMOTE_USER}" "${_REMOTE_USER_HOME}/.claude"
    echo "Set ownership of .claude directory to ${_REMOTE_USER}"
fi

echo "Claude Code Skills directory prepared. Skills will be installed during bootstrap."
```

**Step 2: Verify no auth commands remain**

Run:
```bash
grep -n 'gh auth\|az login\|git clone\|GITHUB_TOKEN' features/claude-skills/install.sh
```
Expected: No output (exit code 1 — no matches)

**Step 3: Verify shellcheck passes**

Run:
```bash
shellcheck features/claude-skills/install.sh
```
Expected: No warnings or errors

**Step 4: Commit**

```bash
git add features/claude-skills/install.sh
git commit -m "feat: strip auth and clone logic from claude-skills Feature

Skills installation moves to config/bootstrap.sh (Phase 4) where
interactive auth is available. Feature now only creates directory
structure and sets ownership."
```
<!-- END_TASK_1 -->

<!-- START_TASK_2 -->
### Task 2: Add post-publish verification step to publish-features.yml

**Files:**
- Modify: `.github/workflows/publish-features.yml` (append after existing steps)

**Step 1: Add verification job to the workflow**

Replace the entire contents of `.github/workflows/publish-features.yml` with:

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

  verify:
    needs: publish
    runs-on: ubuntu-latest
    permissions:
      packages: read
    steps:
      - uses: actions/checkout@v4

      - name: Login to GHCR
        uses: docker/login-action@v3
        with:
          registry: ghcr.io
          username: ${{ github.actor }}
          password: ${{ secrets.GITHUB_TOKEN }}

      - name: Verify all Features are resolvable on GHCR
        run: |
          OWNER="psford"
          REPO="claude-mac-env"
          TAG="${GITHUB_REF_NAME}"
          FEATURES=("claude-skills" "universal-hooks" "csharp-tools" "psford-personal")
          FAILED=0

          for feature in "${FEATURES[@]}"; do
            IMAGE="ghcr.io/${OWNER}/${REPO}/${feature}:${TAG}"
            echo "Verifying: ${IMAGE}"
            if docker manifest inspect "${IMAGE}" > /dev/null 2>&1; then
              echo "  ✓ ${feature}:${TAG} — manifest found"
            else
              echo "  ✗ ${feature}:${TAG} — manifest NOT found"
              FAILED=$((FAILED + 1))
            fi
          done

          if [ "$FAILED" -gt 0 ]; then
            echo ""
            echo "ERROR: ${FAILED} Feature(s) failed manifest verification."
            exit 1
          fi

          echo ""
          echo "All ${#FEATURES[@]} Features verified on GHCR."
```

**Step 2: Verify YAML is valid**

Run:
```bash
python3 -c "import yaml; yaml.safe_load(open('.github/workflows/publish-features.yml'))"
```
Expected: No output (no errors)

**Step 3: Commit**

```bash
git add .github/workflows/publish-features.yml
git commit -m "feat: add post-publish GHCR manifest verification

Adds a 'verify' job that runs after publish, checking each Feature's
OCI manifest is resolvable via docker manifest inspect. Workflow fails
if any Feature is missing."
```
<!-- END_TASK_2 -->

<!-- START_TASK_3 -->
### Task 3: Add CI guard preventing auth commands in Feature install.sh files

**Verifies:** bootstrap-v2.AC1.3

**Files:**
- Modify: `.github/workflows/ci.yml` (add new job)

**Step 1: Add feature-guard job to ci.yml**

Add the following job to the `jobs:` section of `.github/workflows/ci.yml`, after the existing jobs:

```yaml
  feature-guard:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - name: Check Feature install.sh for forbidden auth commands
        run: |
          FORBIDDEN_PATTERNS=(
            "gh auth"
            "az login"
            "GITHUB_TOKEN"
            "git clone"
          )
          FAILED=0

          for install_script in features/*/install.sh; do
            for pattern in "${FORBIDDEN_PATTERNS[@]}"; do
              if grep -qn "$pattern" "$install_script"; then
                echo "FORBIDDEN: '${pattern}' found in ${install_script}:"
                grep -n "$pattern" "$install_script"
                FAILED=$((FAILED + 1))
              fi
            done
          done

          if [ "$FAILED" -gt 0 ]; then
            echo ""
            echo "ERROR: Feature install.sh files must not contain auth-dependent commands."
            echo "Auth belongs in config/bootstrap.sh (postCreateCommand), not in Features."
            exit 1
          fi

          echo "✓ All Feature install.sh files are auth-free."
```

**Step 2: Verify YAML is valid**

Run:
```bash
python3 -c "import yaml; yaml.safe_load(open('.github/workflows/ci.yml'))"
```
Expected: No output (no errors)

**Step 3: Verify the guard would pass with current codebase**

Run locally (simulates what CI will do):
```bash
for install_script in features/*/install.sh; do
  for pattern in "gh auth" "az login" "GITHUB_TOKEN" "git clone"; do
    if grep -qn "$pattern" "$install_script"; then
      echo "FAIL: '${pattern}' in ${install_script}"
    fi
  done
done
echo "Done"
```
Expected: Only "Done" (no FAIL lines, since Task 1 already removed auth from claude-skills)

**Step 4: Commit**

```bash
git add .github/workflows/ci.yml
git commit -m "feat: add CI guard preventing auth commands in Feature install.sh

Fails CI if any Feature install.sh contains gh auth, az login,
GITHUB_TOKEN, or git clone. These operations belong in bootstrap.sh."
```
<!-- END_TASK_3 -->

<!-- START_TASK_4 -->
### Task 4: Verify all Features build in a container

**Files:** None (verification only)

**Step 1: Run a local Docker build to verify Features don't break the image**

Run:
```bash
docker build -t claude-mac-env:phase1-test .
```
Expected: Build succeeds (exit 0). Features install without auth errors.

**Step 2: Verify claude-skills directory was created inside the image**

Run:
```bash
docker run --rm claude-mac-env:phase1-test ls -la /home/claude/.claude/skills/
```
Expected: Directory exists (may be empty — skills are installed at container start, not build time).

**Step 3: Run shellcheck on all Feature install.sh files**

Run:
```bash
find features/ -name 'install.sh' | xargs shellcheck
```
Expected: No errors.

**Step 4: Commit (no changes expected — this is verification only)**

No commit needed. If any verification fails, fix the issue and commit the fix.
<!-- END_TASK_4 -->
