# Bootstrap v2 Implementation Plan — Phase 2

**Goal:** Build the Layer 1 design-by-contract tool functions that do the actual work. Each tool validates preconditions, does one job, verifies postconditions, returns structured results. No UX, no retries.

**Architecture:** Layer 1 tools live in `config/lib/tools.sh` with shared contract helpers in `config/lib/contracts.sh`. Each function: validates preconditions → does work → validates postconditions → returns exit 0 + stdout (success) or exit 1 + stderr (failure). No friendly messages, no retries — those belong to Layers 2 and 3.

**Tech Stack:** Bash, jq, gh CLI, az CLI, git

**Scope:** Phase 2 of 7 from original design

**Codebase verified:** 2026-03-30

---

## Acceptance Criteria Coverage

This phase implements and tests:

### bootstrap-v2.AC2: Bootstrap authenticates user with guided flow
- **bootstrap-v2.AC2.1 Success:** If already authed (`gh auth status` exits 0), prints "✓ Already connected to GitHub as {user}" and skips

### bootstrap-v2.AC3: Git credential helper configured (automatic, invisible to user)
- **bootstrap-v2.AC3.1 Success:** `gh auth setup-git` runs automatically after successful GitHub login — user never sees it
- **bootstrap-v2.AC3.2 Success:** `git config credential.helper` contains "gh" after Phase 2 completes
- **bootstrap-v2.AC3.3 Edge:** If `gh auth setup-git` fails, retry silently once. If still fails, warn but continue (git push may fail later, but setup doesn't block)

### bootstrap-v2.AC4: Skills installed from both repos
- **bootstrap-v2.AC4.1 Success:** ed3d-plugins skills found at `plugins/*/skills/*/SKILL.md` and copied to `~/.claude/skills/`
- **bootstrap-v2.AC4.2 Success:** psford/claude-config skills found and copied to `~/.claude/skills/`
- **bootstrap-v2.AC4.3 Success:** Postcondition check: skill count > 0 and known skill (e.g., brainstorming) exists

### bootstrap-v2.AC5: Claude Code hooks written to settings.json
- **bootstrap-v2.AC5.1 Success:** `~/.claude/settings.json` contains PreToolUse hook entries for commit atomicity, branch protection, force push, destructive rm
- **bootstrap-v2.AC5.2 Success:** Existing settings.json content preserved (jq merge, not overwrite)

### bootstrap-v2.AC6: Symlinks and PATH fixes
- **bootstrap-v2.AC6.1 Success:** `/usr/local/bin/gh --version` exits 0 after Step 5
- **bootstrap-v2.AC6.2 Idempotent:** gh already at `/usr/local/bin/gh` — no-op, no message

### bootstrap-v2.AC7: Secrets loaded
- **bootstrap-v2.AC7.1 Success:** `~/.secrets.env` exists and is non-empty (when provider configured)

---

<!-- START_SUBCOMPONENT_A (tasks 1-2) -->
<!-- START_TASK_1 -->
### Task 1: Create config/lib/contracts.sh — shared precondition/postcondition helpers

**Files:**
- Create: `config/lib/contracts.sh`

**Implementation:**

Create `config/lib/contracts.sh` with shared contract assertion helpers. Follow the project's existing patterns from `config/validate-dependencies.sh` (global counters, named checks, stderr for errors).

Functions to implement:
- `require_command(cmd)` — precondition: command exists on PATH. Returns 0 or writes "error: required command '$cmd' not found" to stderr and returns 1.
- `require_file(path)` — precondition: file exists and is readable. Returns 0 or writes error to stderr and returns 1.
- `require_dir(path)` — precondition: directory exists. Returns 0 or writes error to stderr and returns 1.
- `require_env(var_name)` — precondition: environment variable is set and non-empty. Returns 0 or writes error to stderr and returns 1.
- `require_tty()` — precondition: stdin is a TTY (for interactive prompts). Returns 0 or writes error to stderr and returns 1.
- `ensure_file_exists(path)` — postcondition: file was created. Returns 0 or writes error to stderr and returns 1.
- `ensure_valid_json(path)` — postcondition: file is valid JSON (via `jq .`). Returns 0 or writes error to stderr and returns 1.
- `ensure_exit_zero(description, command...)` — postcondition: command exits 0. Returns 0 or writes error to stderr and returns 1.

All functions must:
- Use `set -euo pipefail` at file top
- Write errors only to stderr
- Return structured exit codes (0/1)
- Have no UX output (no ✓, no progress messages)

**Verification:**
Run: `shellcheck config/lib/contracts.sh`
Expected: No errors

Run: `bash -n config/lib/contracts.sh`
Expected: No syntax errors (exit 0)

**Commit:** `feat: add config/lib/contracts.sh — shared DbC assertion helpers`

<!-- END_TASK_1 -->

<!-- START_TASK_2 -->
### Task 2: Test contracts.sh

**Verifies:** Contract helpers work correctly (foundation for all other tool tests)

**Files:**
- Create: `tests/test-contracts.sh`

**Testing:**
Follow the project's existing test pattern from `tests/test-bootstrap-secrets.sh`:
- `set -uo pipefail` at top
- TEMP_DIR with trap cleanup
- `TESTS_PASSED`/`TESTS_FAILED` counters
- `assert_success`/`assert_failure`/`assert_output_contains` helpers
- Summary at end with exit code

Tests must verify:
- `require_command("bash")` returns 0
- `require_command("nonexistent_tool_xyz")` returns 1 with error on stderr
- `require_file` on existing file returns 0, on missing file returns 1
- `require_dir` on existing dir returns 0, on missing dir returns 1
- `require_env` with set var returns 0, with unset var returns 1
- `ensure_file_exists` on existing file returns 0, on missing returns 1
- `ensure_valid_json` on valid JSON file returns 0, on invalid returns 1

**Verification:**
Run: `bash tests/test-contracts.sh`
Expected: All tests pass

**Commit:** `test: add contract assertion helper tests`

<!-- END_TASK_2 -->
<!-- END_SUBCOMPONENT_A -->

<!-- START_SUBCOMPONENT_B (tasks 3-4) -->
<!-- START_TASK_3 -->
### Task 3: Create config/lib/tools.sh — Layer 1 tool functions

**Files:**
- Create: `config/lib/tools.sh`

**Implementation:**

Create `config/lib/tools.sh` with all Layer 1 tool functions. Source `contracts.sh` at the top. Follow existing patterns from `config/secrets-azure.sh` for function structure, error handling, and variable naming.

Functions to implement (each validates preconditions, does one job, validates postconditions):

**Auth tools:**
- `check_tool(cmd)` — Precondition: none. Runs `command -v "$cmd"` and `"$cmd" --version`. Stdout: version string. Exit 0 if found, exit 1 with error type `missing_tool` on stderr if not.
- `check_gh_auth()` — Precondition: `require_command gh`. Runs `gh auth status`. Stdout: `authed:<username>` or `not_authed`. Exit 0 for both states. Exit 1 with error type `gh_auth_error` on stderr for unexpected errors.
- `check_az_auth()` — Precondition: `require_command az`. Runs `az account show`. Stdout: `authed:<subscription>` or `not_authed`. Exit 0 for both states. Exit 1 with error type `az_auth_error` on stderr for unexpected errors.
- `run_gh_login()` — Precondition: `require_command gh`, `require_tty`. Runs `gh auth login --web --git-protocol https`. Exit 0 on success, exit 1 with error type `gh_login_failed` on stderr.
- `run_gh_setup_git()` — Precondition: `require_command gh`. Runs `gh auth setup-git`. Postcondition: `git config credential.helper` contains "gh". Exit 0 on success, exit 1 with error type `gh_setup_git_failed` on stderr.
- `run_az_login()` — Precondition: `require_command az`, `require_tty`. Runs `az login`. Exit 0 on success, exit 1 with error type `az_login_failed` on stderr.

**Skills tools:**
- `clone_skills_repo(url, name)` — Precondition: `require_command git`, URL is non-empty. Clones to temp dir with `--depth 1`. Stdout: path to cloned directory. The caller is responsible for cleaning up the returned temp directory when done. Exit 0 on success, exit 1 with error type `clone_failed` on stderr.
- `install_skills(source_dir, target_dir)` — Precondition: `require_dir "$source_dir"`, `require_dir "$target_dir"`. Finds `plugins/*/skills/*/SKILL.md` in source_dir. Copies each skill directory to target_dir. Stdout: count of skills installed. Postcondition: at least 1 skill installed (exit 1 with error type `no_skills_found` if zero). Exit 0 on success.

**Config tools:**
- `merge_settings_json(config_fragment, target_path)` — Precondition: `config_fragment` is valid JSON string, target_path parent dir exists. If target_path exists, jq-merge fragment into existing (deep merge). If not, write fragment as new file. Postcondition: `ensure_valid_json "$target_path"`. Exit 0 on success, exit 1 with error type `json_merge_failed` on stderr.
- `fix_symlink(source, target)` — Precondition: `require_file "$source"`. If target already points to source, no-op. Otherwise creates symlink. Postcondition: `"$target" --version` exits 0. Exit 0, exit 1 with error type `symlink_failed` on stderr.
- `load_secrets(provider, config_path)` — Precondition: `require_file "$config_path"`. Sources `secrets-interface.sh` and `secrets-${provider}.sh`. Runs `secrets_validate` then `secrets_inject`. Exit 0 on success, exit 1 with error type `secrets_failed` on stderr.

All functions:
- Use contract helpers from `contracts.sh` for pre/postconditions
- Write structured errors to stderr in format: `error_type:detail_message`
- Write results to stdout
- No UX, no retries, no friendly messages

**Verification:**
Run: `shellcheck config/lib/tools.sh`
Expected: No errors

Run: `bash -n config/lib/tools.sh`
Expected: No syntax errors (exit 0)

**Commit:** `feat: add config/lib/tools.sh — Layer 1 design-by-contract tool functions`

<!-- END_TASK_3 -->

<!-- START_TASK_4 -->
### Task 4: Test tools.sh — contract tests for each tool function

**Verifies:** bootstrap-v2.AC2.1, bootstrap-v2.AC3.2, bootstrap-v2.AC4.1, bootstrap-v2.AC4.2, bootstrap-v2.AC4.3, bootstrap-v2.AC5.1, bootstrap-v2.AC5.2, bootstrap-v2.AC6.1, bootstrap-v2.AC6.2, bootstrap-v2.AC7.1

**Files:**
- Create: `tests/test-tools.sh`

**Testing:**
Follow the project's existing test pattern. Use mock binaries in TEMP_DIR/mock_bin (same pattern as `tests/test-secrets-keychain.sh`).

Tests must verify each tool's preconditions and postconditions:

**check_tool:**
- `check_tool bash` returns 0 with version on stdout
- `check_tool nonexistent_xyz` returns 1 with `missing_tool` on stderr

**check_gh_auth (mocked):**
- Mock `gh` returning exit 0 from `auth status` → stdout contains `authed:`
- Mock `gh` returning exit 1 from `auth status` → stdout contains `not_authed`

**check_az_auth (mocked):**
- Mock `az` returning exit 0 from `account show` → stdout contains `authed:`
- Mock `az` returning exit 1 from `account show` → stdout contains `not_authed`

**run_gh_setup_git (mocked):**
- Mock `gh` and `git` → returns 0, postcondition verified
- Mock `gh` failing → returns 1 with `gh_setup_git_failed` on stderr

**clone_skills_repo (mocked):**
- Create a fake git repo in TEMP_DIR with the expected structure → returns 0 with path
- Mock `git clone` failing → returns 1 with `clone_failed` on stderr

**install_skills:**
- Create source_dir with `plugins/test-plugin/skills/brainstorming/SKILL.md` structure → returns 0, count > 0
- Create empty source_dir (no skills) → returns 1 with `no_skills_found` on stderr
- bootstrap-v2.AC4.3: After install, verify `brainstorming` skill directory exists in target

**merge_settings_json:**
- Merge into non-existent target → creates new file, `jq .` passes (bootstrap-v2.AC5.1)
- Merge into existing target → preserves existing keys, adds new ones (bootstrap-v2.AC5.2)
- Invalid JSON fragment → returns 1 with `json_merge_failed` on stderr

**fix_symlink:**
- Source exists, target doesn't → creates symlink, returns 0 (bootstrap-v2.AC6.1)
- Source exists, target already correct → no-op, returns 0 (bootstrap-v2.AC6.2)

**load_secrets (mocked):**
- Mock secrets provider returning success → returns 0 (bootstrap-v2.AC7.1)
- Mock secrets provider returning failure → returns 1 with `secrets_failed` on stderr

**Verification:**
Run: `bash tests/test-tools.sh`
Expected: All tests pass

**Commit:** `test: add Layer 1 tool function contract tests`

<!-- END_TASK_4 -->
<!-- END_SUBCOMPONENT_B -->

<!-- START_TASK_5 -->
### Task 5: Verify all tests pass together and shellcheck clean

**Files:** None (verification only)

**Step 1: Run all new tests**

Run:
```bash
bash tests/test-contracts.sh && bash tests/test-tools.sh
```
Expected: All tests pass in both files

**Step 2: Run shellcheck on all new files**

Run:
```bash
shellcheck config/lib/contracts.sh config/lib/tools.sh tests/test-contracts.sh tests/test-tools.sh
```
Expected: No errors

**Step 3: Verify existing tests still pass**

Run:
```bash
bash tests/test-bootstrap-secrets.sh
```
Expected: Existing tests still pass (no regressions)
<!-- END_TASK_5 -->
