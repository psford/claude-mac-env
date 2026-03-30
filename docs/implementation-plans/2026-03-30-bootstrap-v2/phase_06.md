# Bootstrap v2 Implementation Plan — Phase 6

**Goal:** Add CI checks that structurally prevent the failure modes that caused the original bootstrap breakage from recurring: auth commands in Features, invalid JSON generation, and broken external repo URLs.

**Architecture:** Adds three new CI jobs to `.github/workflows/ci.yml`: static analysis of Feature install.sh files, JSON validation of rendered devcontainer.json, and external reference validation. Also adds post-publish manifest verification to `publish-features.yml` (already partially done in Phase 1) and a new `validate_chain_external_refs()` function to `config/validate-dependencies.sh`.

**Tech Stack:** GitHub Actions, Bash, jq, gh CLI

**Scope:** Phase 6 of 7 from original design

**Codebase verified:** 2026-03-30

---

## Acceptance Criteria Coverage

This phase implements and tests:

### bootstrap-v2.AC10: CI enforces contracts
- **bootstrap-v2.AC10.1 Success:** CI fails if Feature install.sh contains forbidden auth commands
- **bootstrap-v2.AC10.2 Success:** CI fails if rendered devcontainer.json is invalid JSON
- **bootstrap-v2.AC10.3 Success:** CI fails if hardcoded repo URLs don't resolve via `gh repo view`
- **bootstrap-v2.AC10.4 Success:** Post-publish CI verifies all GHCR Feature manifests exist

---

<!-- START_TASK_1 -->
### Task 1: Add JSON validation CI job

**Files:**
- Modify: `.github/workflows/ci.yml` (add new job)

**Implementation:**

Add a `json-validate` job to ci.yml that renders devcontainer.json using a test config and validates the output with `jq .`.

```yaml
  json-validate:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - name: Create test config
        run: |
          cat > .user-config.json <<'EOF'
          {
            "githubUser": "ci-test",
            "projectDirs": ["/tmp/test-project"],
            "baseImage": "ubuntu:24.04",
            "features": {
              "claude-skills": {},
              "universal-hooks": {}
            },
            "secrets": {
              "provider": "none"
            }
          }
          EOF

      - name: Render devcontainer.json
        run: |
          # Source the render function and run it
          # This tests that the jq-based rendering produces valid JSON
          source config/lib/tools.sh
          render_devcontainer_json .user-config.json .devcontainer/devcontainer.json.template .devcontainer/devcontainer.json

      - name: Validate rendered JSON
        run: |
          echo "Validating .devcontainer/devcontainer.json..."
          if jq . .devcontainer/devcontainer.json > /dev/null 2>&1; then
            echo "✓ Valid JSON"
          else
            echo "✗ Invalid JSON!"
            cat .devcontainer/devcontainer.json
            exit 1
          fi

      - name: Validate template is valid JSON
        run: |
          echo "Validating .devcontainer/devcontainer.json.template..."
          jq . .devcontainer/devcontainer.json.template > /dev/null
```

**Verification:**
Run: `python3 -c "import yaml; yaml.safe_load(open('.github/workflows/ci.yml'))"`
Expected: No errors

**Commit:** `feat: add CI job to validate rendered devcontainer.json is valid JSON`

<!-- END_TASK_1 -->

<!-- START_TASK_2 -->
### Task 2: Add external reference validation to validate-dependencies.sh

**Files:**
- Modify: `config/validate-dependencies.sh` (add new function before `validate_all`)

**Implementation:**

Add a `validate_chain_external_refs()` function that checks all hardcoded repo URLs in the codebase resolve via `gh repo view`. This catches hallucinated or renamed repos before they break the bootstrap at runtime.

The function should:
1. Extract repo URLs from known locations:
   - `config/lib/tools.sh` (skills repo URLs in `clone_skills_repo` calls)
   - `setup.sh` (any hardcoded GitHub URLs)
2. For each URL, run `gh repo view <owner/repo> --json name` with a timeout
3. Report success/failure per URL
4. Increment `VALIDATION_ERRORS` for each failed URL

Follow the existing validation chain pattern: print a header, check each item, return 0 (individual failures tracked via counter).

Also add `validate_chain_external_refs` to the `validate_all()` function, gated behind a check for `gh auth status` (can't validate refs without auth).

**Verification:**
Run: `shellcheck config/validate-dependencies.sh`
Expected: No errors

**Commit:** `feat: add validate_chain_external_refs() for hardcoded repo URL validation`

<!-- END_TASK_2 -->

<!-- START_TASK_3 -->
### Task 3: Add external-refs CI job

**Files:**
- Modify: `.github/workflows/ci.yml` (add new job)

**Implementation:**

Add an `external-refs` job that runs `validate_chain_external_refs()` in CI. This job needs `gh` auth to check repo URLs.

```yaml
  external-refs:
    runs-on: ubuntu-latest
    permissions:
      contents: read
    env:
      GH_TOKEN: ${{ secrets.GITHUB_TOKEN }}
    steps:
      - uses: actions/checkout@v4

      - name: Validate external repo references
        run: |
          source config/validate-dependencies.sh
          VALIDATION_ERRORS=0
          VALIDATION_WARNINGS=0
          validate_chain_external_refs
          if [[ $VALIDATION_ERRORS -gt 0 ]]; then
            echo "FAILED: $VALIDATION_ERRORS broken external reference(s)"
            exit 1
          fi
          echo "✓ All external references valid"
```

**Verification:**
Run: `python3 -c "import yaml; yaml.safe_load(open('.github/workflows/ci.yml'))"`
Expected: No errors

**Commit:** `feat: add CI job to validate hardcoded repo URLs resolve`

<!-- END_TASK_3 -->

<!-- START_TASK_4 -->
### Task 4: Verify Phase 1's feature-guard and publish verification are complete

**Verifies:** bootstrap-v2.AC10.1, bootstrap-v2.AC10.4

**Files:** None (verification only)

**Step 1: Verify feature-guard job exists in ci.yml**

The feature-guard job was added in Phase 1 Task 3. Verify it's present:
```bash
grep -q 'feature-guard' .github/workflows/ci.yml
```
Expected: Exit 0 (found)

**Step 2: Verify publish verification exists in publish-features.yml**

The verify job was added in Phase 1 Task 2. Verify it's present:
```bash
grep -q 'docker manifest inspect' .github/workflows/publish-features.yml
```
Expected: Exit 0 (found)

**Step 3: Run shellcheck on all workflow scripts**

Run:
```bash
shellcheck config/validate-dependencies.sh
```
Expected: No errors
<!-- END_TASK_4 -->

<!-- START_TASK_5 -->
### Task 5: Test validate_chain_external_refs locally

**Verifies:** bootstrap-v2.AC10.3

**Files:**
- Create: `tests/test-validate-external-refs.sh`

**Testing:**
Follow the project's existing test pattern.

Tests must verify:

**Valid ref detection:**
- Mock `gh repo view` returning success for a known repo → counter stays at 0

**Invalid ref detection:**
- Mock `gh repo view` returning failure for a bad URL → `VALIDATION_ERRORS` incremented

**No gh auth available:**
- Mock `gh auth status` returning failure → function skips gracefully (no crash)

**Verification:**
Run: `bash tests/test-validate-external-refs.sh`
Expected: All tests pass

**Commit:** `test: add external reference validation tests`

<!-- END_TASK_5 -->
