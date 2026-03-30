# Bootstrap v2 Implementation Plan — Phase 3

**Goal:** Build the Layer 2 error handling module that accepts structured errors from Layer 1 tools and returns recovery actions (retry/skip/abort) with plain-English user messages.

**Architecture:** Layer 2 sits between Layer 1 (tools) and Layer 3 (orchestration). It has a single dispatch function `handle_error(error_type, detail, context)` that routes to specific handlers. Each handler returns a recovery action and a human-readable message. Layer 2 knows retry policy but NOT UX flow or step ordering.

**Tech Stack:** Bash

**Scope:** Phase 3 of 7 from original design

**Codebase verified:** 2026-03-30

---

## Acceptance Criteria Coverage

This phase implements and tests:

### bootstrap-v2.AC2: Bootstrap authenticates user with guided flow
- **bootstrap-v2.AC2.3 Success:** On login failure, explains common causes (browser didn't open, network issue) and offers immediate retry
- **bootstrap-v2.AC2.8 Edge:** User cancels gh login 3 times — bootstrap exits with friendly message ("No worries — run this command when you're ready: ...")

### bootstrap-v2.AC4: Skills installed from both repos
- **bootstrap-v2.AC4.4 Failure:** Clone fails — Layer 2 offers retry ("Couldn't reach GitHub. Check your connection and try again?")
- **bootstrap-v2.AC4.5 Failure:** Zero skills found after clone — Layer 2 returns abort with clear message naming the bad directory pattern

### bootstrap-v2.AC5: Claude Code hooks written to settings.json
- **bootstrap-v2.AC5.3 Failure:** Resulting settings.json is invalid JSON — Layer 2 returns abort with "settings file is corrupt"

### bootstrap-v2.AC6: Symlinks and PATH fixes
- **bootstrap-v2.AC6.3 Failure:** gh not found anywhere — Layer 2 returns skip, non-critical

### bootstrap-v2.AC7: Secrets loaded
- **bootstrap-v2.AC7.3 Failure:** Provider error — Layer 2 returns skip with friendly message ("Secrets couldn't load. Your environment will work, but some features need credentials. Run `bootstrap.sh --secrets-only` to try again later.")

---

<!-- START_SUBCOMPONENT_A (tasks 1-2) -->
<!-- START_TASK_1 -->
### Task 1: Create config/lib/errors.sh — Layer 2 error handling

**Files:**
- Create: `config/lib/errors.sh`

**Implementation:**

Create `config/lib/errors.sh` with the error dispatch function and per-type handlers. Follow existing project patterns (`set -euo pipefail`, function naming with underscores, stderr for errors).

**Core dispatch function:**
- `handle_error(error_type, detail, context)` — Looks up handler for error_type, calls it, returns structured result. Output format on stdout: `action:message` where action is one of `retry`, `skip`, `abort`. If no handler found for error_type, returns `abort:Unknown error: $detail`.

**Error type handlers (each returns `action:message` on stdout):**

| Error Type | Handler | Max Retries | Action | Message Pattern |
|---|---|---|---|---|
| `missing_tool` | `handle_missing_tool` | 0 | abort | "'{tool}' should be installed in the container image. Something is wrong with the Dockerfile." |
| `gh_auth_error` | `handle_auth_error` | 0 | abort | "Unexpected error checking GitHub auth: {detail}" |
| `gh_login_failed` | `handle_gh_login_failed` | 3 | retry (then abort) | retry: "That didn't work. Common reasons: browser didn't open, network issue. Try again?" / abort: "No worries — run this command when you're ready: gh auth login --web --git-protocol https" |
| `az_auth_error` | `handle_auth_error` | 0 | abort | "Unexpected error checking Azure auth: {detail}" |
| `az_login_failed` | `handle_az_login_failed` | 3 | retry (then abort) | retry: "Azure login didn't work. Check your browser and try again?" / abort: "You can add Azure later by running: az login" |
| `gh_setup_git_failed` | `handle_gh_setup_git_failed` | 1 | retry (then skip) | retry: silent / skip: "Git credential helper couldn't be configured. git push may need manual auth." |
| `clone_failed` | `handle_clone_failed` | 2 | retry (then abort) | retry: "Couldn't reach GitHub. Check your connection and try again?" / abort: "Still can't reach GitHub. Check your network and re-run bootstrap." |
| `no_skills_found` | `handle_no_skills_found` | 0 | abort | "Cloned the repo but found zero skills at plugins/*/skills/*/SKILL.md. Repository structure may have changed." |
| `json_merge_failed` | `handle_json_merge_failed` | 0 | abort | "Settings file is corrupt — couldn't write valid JSON. Check ~/.claude/settings.json" |
| `symlink_failed` | `handle_symlink_failed` | 0 | skip | "gh symlink couldn't be created. This is non-critical — GitHub CLI may not be in your PATH." |
| `secrets_failed` | `handle_secrets_failed` | 0 | skip | "Secrets couldn't load. Your environment will work, but some features need credentials. Run 'bootstrap.sh --secrets-only' to try again later." |

**Retry tracking:**
- Module-level associative array `declare -A ERROR_RETRY_COUNT` tracks retry count per error_type.
- On each call to `handle_error`, increment `ERROR_RETRY_COUNT[$error_type]`.
- If count exceeds max retries for that type, return the "exhausted" action (abort or skip depending on type).

**All messages must pass the brother-in-law test:** Plain English, no jargon, actionable next steps. No stack traces, no error codes, no "contact support."

**Verification:**
Run: `shellcheck config/lib/errors.sh`
Expected: No errors

Run: `bash -n config/lib/errors.sh`
Expected: No syntax errors (exit 0)

**Commit:** `feat: add config/lib/errors.sh — Layer 2 error handling with retry policy`

<!-- END_TASK_1 -->

<!-- START_TASK_2 -->
### Task 2: Test errors.sh — verify each error type maps to correct action and message

**Verifies:** bootstrap-v2.AC2.3, bootstrap-v2.AC2.8, bootstrap-v2.AC4.4, bootstrap-v2.AC4.5, bootstrap-v2.AC5.3, bootstrap-v2.AC6.3, bootstrap-v2.AC7.3

**Files:**
- Create: `tests/test-errors.sh`

**Testing:**
Follow the project's existing test pattern from `tests/test-bootstrap-secrets.sh`.

Tests must verify:

**Action mapping (each error type returns correct action):**
- `handle_error missing_tool "jq" ""` → stdout starts with `abort:`
- `handle_error gh_login_failed "" ""` → stdout starts with `retry:` (first call)
- `handle_error clone_failed "" ""` → stdout starts with `retry:` (first call)
- `handle_error no_skills_found "" ""` → stdout starts with `abort:`
- `handle_error json_merge_failed "" ""` → stdout starts with `abort:`
- `handle_error symlink_failed "" ""` → stdout starts with `skip:`
- `handle_error secrets_failed "" ""` → stdout starts with `skip:`

**Retry exhaustion (bootstrap-v2.AC2.8):**
- Call `handle_error gh_login_failed "" ""` 4 times. First 3 return `retry:`. Fourth returns `abort:` with message containing "No worries"

**Message quality (brother-in-law test):**
- `handle_error clone_failed "" ""` message contains "Couldn't reach GitHub"
- `handle_error secrets_failed "" ""` message contains "Secrets couldn't load"
- `handle_error json_merge_failed "" ""` message contains "corrupt"
- `handle_error missing_tool "jq" ""` message contains "Dockerfile"

**Unknown error type:**
- `handle_error unknown_xyz "something broke" ""` → stdout starts with `abort:` and contains "Unknown error"

**Verification:**
Run: `bash tests/test-errors.sh`
Expected: All tests pass

**Commit:** `test: add Layer 2 error handler tests`

<!-- END_TASK_2 -->
<!-- END_SUBCOMPONENT_A -->

<!-- START_TASK_3 -->
### Task 3: Verify all Phase 2 and Phase 3 tests pass together

**Files:** None (verification only)

**Step 1: Run all Layer 1 and Layer 2 tests**

Run:
```bash
bash tests/test-contracts.sh && bash tests/test-tools.sh && bash tests/test-errors.sh
```
Expected: All tests pass

**Step 2: Run shellcheck on all new files**

Run:
```bash
shellcheck config/lib/contracts.sh config/lib/tools.sh config/lib/errors.sh tests/test-contracts.sh tests/test-tools.sh tests/test-errors.sh
```
Expected: No errors
<!-- END_TASK_3 -->
