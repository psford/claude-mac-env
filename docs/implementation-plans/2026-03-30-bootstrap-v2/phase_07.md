# Bootstrap v2 Implementation Plan — Phase 7

**Goal:** Add a full E2E integration test that builds the container from generated devcontainer.json, runs bootstrap.sh with mock auth, and verifies all postconditions. Also add CLAUDE_CODE env var support to the pre-commit permission hook.

**Architecture:** The E2E test builds a real container, runs bootstrap.sh inside it, and checks every postcondition (skills installed, settings.json valid, hooks present, credential helper configured). The pre-commit hook already skips on non-TTY (`! [ -t 0 ]`), but needs an additional bypass for `CLAUDE_CODE=1` env var.

**Tech Stack:** GitHub Actions, Docker, Bash

**Scope:** Phase 7 of 7 from original design

**Codebase verified:** 2026-03-30

---

## Acceptance Criteria Coverage

This phase implements and tests:

### bootstrap-v2.AC11: E2E integration test
- **bootstrap-v2.AC11.1 Success:** CI builds full container from generated devcontainer.json
- **bootstrap-v2.AC11.2 Success:** Bootstrap runs inside container and all postconditions pass (skills > 0, settings.json valid, hooks installed, credential helper set)
- **bootstrap-v2.AC11.3 Failure:** E2E job fails if any bootstrap postcondition is unmet

### bootstrap-v2.AC12: Pre-commit hook non-interactive support
- **bootstrap-v2.AC12.1 Success:** Hook exits 0 when stdin is not a TTY (e.g., Claude Code, CI)
- **bootstrap-v2.AC12.2 Success:** Hook still prompts when stdin is a TTY (interactive terminal)
- **bootstrap-v2.AC12.3 Edge:** `CLAUDE_CODE=1` env var bypasses prompt regardless of TTY state

---

<!-- START_TASK_1 -->
### Task 1: Add CLAUDE_CODE env var bypass to pre-commit-permission.sh

**Files:**
- Modify: `features/universal-hooks/hooks/pre-commit-permission.sh` (lines 9-12)

**Implementation:**

The hook at `features/universal-hooks/hooks/pre-commit-permission.sh` currently has this non-TTY check (lines 9-12):

```bash
# Skip in non-interactive contexts (CI, automated processes)
if [ ! -t 0 ]; then
    exit 0
fi
```

Replace lines 9-12 with:

```bash
# Skip in non-interactive contexts (CI, automated processes, Claude Code)
if [ ! -t 0 ] || [ "${CLAUDE_CODE:-}" = "1" ]; then
    exit 0
fi
```

This adds the `CLAUDE_CODE=1` env var bypass while preserving the existing non-TTY detection. The `${CLAUDE_CODE:-}` default prevents `set -u` from failing on unset variable.

**Verification:**
Run: `shellcheck features/universal-hooks/hooks/pre-commit-permission.sh`
Expected: No errors

Run (verify non-TTY still works):
```bash
echo "" | bash features/universal-hooks/hooks/pre-commit-permission.sh
```
Expected: Exit 0 (stdin is not a TTY in pipe context)

Run (verify CLAUDE_CODE bypass):
```bash
CLAUDE_CODE=1 bash features/universal-hooks/hooks/pre-commit-permission.sh
```
Expected: Exit 0

**Commit:** `feat: add CLAUDE_CODE=1 env var bypass to pre-commit permission hook`

<!-- END_TASK_1 -->

<!-- START_TASK_2 -->
### Task 2: Create scripts/test-e2e-bootstrap.sh — E2E postcondition verifier

**Files:**
- Create: `scripts/test-e2e-bootstrap.sh`

**Implementation:**

Create an E2E test script that runs inside the container after bootstrap.sh completes. It verifies every bootstrap postcondition.

The script should follow the existing `scripts/validate.sh` pattern (colored output, pass/fail counters, summary) but focus specifically on bootstrap postconditions.

Checks to implement:
1. **Skills installed:** `~/.claude/skills/` has > 0 directories
2. **Known skill present:** `~/.claude/skills/brainstorming/SKILL.md` exists
3. **settings.json valid:** `jq . ~/.claude/settings.json` exits 0
4. **Hooks in settings.json:** `jq '.hooks' ~/.claude/settings.json` contains PreToolUse entries
5. **Credential helper:** `git config credential.helper` output is non-empty (may contain "gh" if gh auth was run)
6. **gh symlink:** `which gh` returns a path (may be /usr/local/bin/gh or /usr/bin/gh)
7. **Bootstrap idempotent:** Running bootstrap.sh a second time produces no errors

Each check: print "✓ <check>" on success, "✗ <check>" on failure, increment counters. Exit 1 if any check fails.

**Verification:**
Run: `shellcheck scripts/test-e2e-bootstrap.sh`
Expected: No errors

**Commit:** `feat: add E2E bootstrap postcondition verification script`

<!-- END_TASK_2 -->

<!-- START_TASK_3 -->
### Task 3: Add E2E CI job to ci.yml

**Files:**
- Modify: `.github/workflows/ci.yml` (add new job)

**Implementation:**

Add an `e2e` job that builds the full container, runs bootstrap.sh with mock auth (since CI has no interactive terminal), and runs the postcondition verifier.

```yaml
  e2e:
    runs-on: ubuntu-latest
    needs: [lint, build]
    steps:
      - uses: actions/checkout@v4

      - name: Create test config
        run: |
          cat > .user-config.json <<'EOF'
          {
            "githubUser": "ci-test",
            "projectDirs": [],
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

      - name: Render devcontainer.json for test
        run: |
          source config/lib/tools.sh
          render_devcontainer_json .user-config.json .devcontainer/devcontainer.json.template .devcontainer/devcontainer.json

      - name: Build container
        run: docker build -t claude-mac-env:e2e .

      - name: Run bootstrap and verify postconditions
        run: |
          docker run --rm \
            -v "$(pwd)/config:/workspaces/.claude-mac-env/config:ro" \
            -v "$(pwd)/scripts:/workspaces/.claude-mac-env/scripts:ro" \
            -v "$(pwd)/.user-config.json:/workspaces/.claude-mac-env/.user-config.json:ro" \
            -e CLAUDE_CODE=1 \
            -e BOOTSTRAP_MOCK_AUTH=1 \
            claude-mac-env:e2e \
            bash -c "bash /workspaces/.claude-mac-env/config/bootstrap.sh && bash /workspaces/.claude-mac-env/scripts/test-e2e-bootstrap.sh"
```

Note: `BOOTSTRAP_MOCK_AUTH=1` is an environment variable that `bootstrap.sh` should check in step 2 (GitHub auth) and step 3 (Azure auth) to skip interactive login prompts in CI. This mock flag must be added to `config/bootstrap.sh` as part of this task.

**Step 2: Add BOOTSTRAP_MOCK_AUTH support to config/bootstrap.sh**

In `step_github_auth()` and `step_azure_auth()`, add at the top:
```bash
if [[ "${BOOTSTRAP_MOCK_AUTH:-}" == "1" ]]; then
    step_skip "Auth skipped (mock mode)"
    return 0
fi
```

This allows CI to run the full bootstrap flow without interactive auth.

**Verification:**
Run: `python3 -c "import yaml; yaml.safe_load(open('.github/workflows/ci.yml'))"`
Expected: No errors

**Commit:** `feat: add E2E CI job — builds container, runs bootstrap, verifies postconditions`

<!-- END_TASK_3 -->

<!-- START_TASK_4 -->
### Task 4: Test pre-commit hook non-interactive behavior

**Verifies:** bootstrap-v2.AC12.1, bootstrap-v2.AC12.2, bootstrap-v2.AC12.3

**Files:**
- Create: `tests/test-pre-commit-hook.sh`

**Testing:**
Follow the project's existing test pattern.

Tests must verify:

**bootstrap-v2.AC12.1 — non-TTY bypass:**
- Pipe input to hook: `echo "" | bash features/universal-hooks/hooks/pre-commit-permission.sh` → exit 0

**bootstrap-v2.AC12.3 — CLAUDE_CODE bypass:**
- Run with env var: `CLAUDE_CODE=1 bash features/universal-hooks/hooks/pre-commit-permission.sh < /dev/null` → exit 0
- Run without env var but with TTY simulation would prompt (test by checking that the `read` command is reached — mock by checking script behavior with non-TTY stdin)

**Edge cases:**
- `CLAUDE_CODE=0` does NOT bypass (only `1` triggers bypass)
- Unset `CLAUDE_CODE` does NOT bypass

**Verification:**
Run: `bash tests/test-pre-commit-hook.sh`
Expected: All tests pass

**Commit:** `test: add pre-commit hook non-interactive bypass tests`

<!-- END_TASK_4 -->

<!-- START_TASK_5 -->
### Task 5: Final verification — all tests pass, shellcheck clean

**Files:** None (verification only)

**Step 1: Run all test files**

Run:
```bash
bash tests/test-contracts.sh && \
bash tests/test-tools.sh && \
bash tests/test-errors.sh && \
bash tests/test-bootstrap.sh && \
bash tests/test-render-devcontainer.sh && \
bash tests/test-validate-external-refs.sh && \
bash tests/test-pre-commit-hook.sh
```
Expected: All tests pass

**Step 2: Run shellcheck on all shell scripts**

Run:
```bash
find . -name '*.sh' -not -path './.git/*' | xargs shellcheck
```
Expected: No errors

**Step 3: Verify CI workflow YAML is valid**

Run:
```bash
python3 -c "import yaml; yaml.safe_load(open('.github/workflows/ci.yml'))"
python3 -c "import yaml; yaml.safe_load(open('.github/workflows/publish-features.yml'))"
```
Expected: No errors
<!-- END_TASK_5 -->
