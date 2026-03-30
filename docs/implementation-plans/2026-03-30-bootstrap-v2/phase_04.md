# Bootstrap v2 Implementation Plan — Phase 4

**Goal:** Build the Layer 3 orchestrator (`config/bootstrap.sh`) that chains Layer 1 tools and Layer 2 error handling into a 6-step guided user flow. Each step is idempotent — if already done, prints "✓" and moves on. If killed and re-run, resumes from the first incomplete step.

**Architecture:** `config/bootstrap.sh` is the single `postCreateCommand` entry point. It sources `config/lib/tools.sh` and `config/lib/errors.sh`, reads identity from `.user-config.json`, and runs 6 steps: check tools → GitHub auth → Azure auth (conditional) → install skills → configure Claude Code → load secrets. Each step: check if done → if yes, skip → if no, call Layer 1 → on error, call Layer 2 → act on response (retry/skip/abort).

**Tech Stack:** Bash, jq

**Scope:** Phase 4 of 7 from original design

**Codebase verified:** 2026-03-30

---

## Acceptance Criteria Coverage

This phase implements and tests:

### bootstrap-v2.AC2: Bootstrap authenticates user with guided flow
- **bootstrap-v2.AC2.1 Success:** If already authed (`gh auth status` exits 0), prints "✓ Already connected to GitHub as {user}" and skips
- **bootstrap-v2.AC2.2 Success:** If not authed, explains what's about to happen in plain English, runs `gh auth login --web --git-protocol https`, waits for completion
- **bootstrap-v2.AC2.3 Success:** On login failure, explains common causes (browser didn't open, network issue) and offers immediate retry
- **bootstrap-v2.AC2.4 Success:** After successful gh login, runs `gh auth setup-git` automatically (user never sees this)
- **bootstrap-v2.AC2.5 Success:** For psford, if Azure not authed, explains why Azure is needed ("Your secrets are stored in Azure Key Vault") and runs `az login`
- **bootstrap-v2.AC2.6 Edge:** Non-psford with secrets.provider == "azure" — explains Azure is needed for their secrets config, offers login or skip ("You can add this later")
- **bootstrap-v2.AC2.7 Edge:** Non-psford with secrets.provider != "azure" — no Azure mention at all
- **bootstrap-v2.AC2.8 Edge:** User cancels gh login 3 times — bootstrap exits with friendly message ("No worries — run this command when you're ready: ...")

### bootstrap-v2.AC4: Skills installed from both repos
- **bootstrap-v2.AC4.6 Idempotent:** If skills already installed (count > 0, known skill present), prints "✓ Skills already installed" and skips

### bootstrap-v2.AC5: Claude Code hooks written to settings.json
- **bootstrap-v2.AC5.4 Edge:** settings.json doesn't exist yet — bootstrap creates it from scratch
- **bootstrap-v2.AC5.5 Idempotent:** If settings.json already has expected hook keys, prints "✓ Claude Code hooks configured" and skips

### bootstrap-v2.AC7: Secrets loaded
- **bootstrap-v2.AC7.2 Edge:** secrets.provider == "skip" — Step 6 skips cleanly, no warning
- **bootstrap-v2.AC7.4 Idempotent:** If ~/.secrets.env exists and is recent, prints "✓ Secrets loaded" and skips

### bootstrap-v2.AC8: Bootstrap is idempotent and recoverable
- **bootstrap-v2.AC8.1 Success:** Re-running bootstrap after successful completion produces no errors and no re-prompts
- **bootstrap-v2.AC8.2 Success:** Killing bootstrap mid-run and re-running resumes from the first incomplete step
- **bootstrap-v2.AC8.3 Success:** Each step independently detects whether its work is already done
- **bootstrap-v2.AC8.4 Edge:** User re-runs setup.sh from scratch — project directories and config from .user-config.json are preserved, not re-prompted

---

<!-- START_TASK_1 -->
### Task 1: Create config/bootstrap.sh — Layer 3 orchestrator skeleton

**Files:**
- Create: `config/bootstrap.sh`

**Implementation:**

Create `config/bootstrap.sh` with the full 6-step orchestration flow. This is the largest single file in the bootstrap-v2 design.

Structure:
1. Shebang, `set -euo pipefail`, SCRIPT_DIR resolution
2. Source `config/lib/tools.sh` and `config/lib/errors.sh`
3. Read identity from `.user-config.json` via jq
4. Define UX helper functions: `step_header(n, total, message)`, `step_skip(message)`, `step_done(message)`
5. Define the 6 step functions, each idempotent
6. Main function that runs steps 1-6 in order, with `--secrets-only` flag support

**Step functions:**

`step_check_tools()` — Step 1 of 6: Checking tools
- For each of git, curl, jq, node, python3, claude: call `check_tool`
- On error: `handle_error missing_tool` → abort (Dockerfile is broken)
- Always runs (fast, no side effects, no idempotency check needed)

`step_github_auth()` — Step 2 of 6: Connecting to GitHub
- Call `check_gh_auth`
- If `authed:<user>`: print "✓ Already connected to GitHub as {user}" and return
- If `not_authed`: print explanation, call `run_gh_login`
- On error: `handle_error gh_login_failed` → retry or abort
- After success: call `run_gh_setup_git` silently
- On setup-git error: `handle_error gh_setup_git_failed` → retry once then skip

`step_azure_auth(github_user, secrets_provider)` — Step 3 of 6: Connecting to Azure
- If `github_user == "psford"`: Azure is required. Check `check_az_auth`. If not authed, explain and run `run_az_login`.
- If `secrets_provider == "azure"` (non-psford): Explain Azure is needed, offer login or skip
- Otherwise: skip silently (no output)

`step_install_skills(github_user)` — Step 4 of 6: Installing skills
- Idempotency: check if `~/.claude/skills/` has > 0 directories and `brainstorming` skill exists → skip
- Clone ed3d-plugins via `clone_skills_repo`, install via `install_skills`
- Clone psford/claude-config via `clone_skills_repo`, install via `install_skills`
- On clone error: `handle_error clone_failed` → retry or abort
- On no skills: `handle_error no_skills_found` → abort

`step_configure_claude(github_user)` — Step 5 of 6: Configuring Claude Code
- Idempotency: check if `~/.claude/settings.json` already contains expected hook keys → skip
- Build hook config JSON fragment with jq (PreToolUse hooks for commit atomicity, branch protection, force push, destructive rm)
- Call `merge_settings_json` with the fragment
- Call `fix_symlink` for gh → /usr/local/bin/gh
- On JSON error: `handle_error json_merge_failed` → abort
- On symlink error: `handle_error symlink_failed` → skip

`step_load_secrets(secrets_provider, config_path)` — Step 6 of 6: Loading secrets
- If `secrets_provider` is empty, "none", or "skip": skip cleanly
- Idempotency: if `~/.secrets.env` exists and is non-empty and less than 24h old → skip
- Call `load_secrets`
- On error: `handle_error secrets_failed` → skip with friendly message

**Main function:**
- Parse args: `--secrets-only` flag runs only step 6
- Read config: `USER_CONFIG` path, extract `githubUser`, `secrets.provider`
- Print banner: "Bootstrap v2 — Setting up your environment"
- Run steps 1-6 (or just step 6 if --secrets-only)
- Print summary: "✓ Environment ready!" or error summary

**Verification:**
Run: `shellcheck config/bootstrap.sh`
Expected: No errors

Run: `bash -n config/bootstrap.sh`
Expected: No syntax errors (exit 0)

**Commit:** `feat: add config/bootstrap.sh — Layer 3 orchestrator with 6-step guided flow`

<!-- END_TASK_1 -->

<!-- START_TASK_2 -->
### Task 2: Update postCreateCommand to use bootstrap.sh

**Files:**
- Modify: `.devcontainer/devcontainer.json` (change `postCreateCommand` value)
- Modify: `.devcontainer/devcontainer.json.template` (change `postCreateCommand` value, if it exists)

**Step 1: Update devcontainer.json**

Change the `postCreateCommand` line from:
```json
"postCreateCommand": "bash /workspaces/.claude-mac-env/config/bootstrap-secrets.sh || true"
```
to:
```json
"postCreateCommand": "bash /workspaces/.claude-mac-env/config/bootstrap.sh"
```

Note: Remove the `|| true` — bootstrap.sh handles its own errors gracefully via Layer 2. It should never crash the container creation, but if it does, we want to know about it.

**Step 2: Update the template if it exists**

Apply the same change to `.devcontainer/devcontainer.json.template`.

**Step 3: Commit**

```bash
git add .devcontainer/devcontainer.json .devcontainer/devcontainer.json.template
git commit -m "feat: update postCreateCommand to use bootstrap.sh

Replaces bootstrap-secrets.sh with the full Layer 3 orchestrator.
Removes || true — bootstrap.sh handles errors via Layer 2."
```

<!-- END_TASK_2 -->

<!-- START_TASK_3 -->
### Task 3: Test bootstrap.sh — idempotency and error handling

**Verifies:** bootstrap-v2.AC2.1, bootstrap-v2.AC2.5, bootstrap-v2.AC2.7, bootstrap-v2.AC4.6, bootstrap-v2.AC5.5, bootstrap-v2.AC7.2, bootstrap-v2.AC7.4, bootstrap-v2.AC8.1, bootstrap-v2.AC8.3

**Files:**
- Create: `tests/test-bootstrap.sh`

**Testing:**
Follow the project's existing test pattern. Use mock binaries for gh, az, git, claude.

Tests must verify:

**Idempotency (bootstrap-v2.AC8.1, AC8.2, AC8.3):**
- Pre-populate `~/.claude/skills/brainstorming/SKILL.md` → step 4 prints skip message containing "already installed"
- Pre-populate `~/.claude/settings.json` with expected hook keys → step 5 prints skip message containing "hooks configured"
- Pre-populate `~/.secrets.env` (recent) → step 6 prints skip message containing "Secrets loaded"
- **Kill-and-resume (AC8.2):** Pre-populate skills (step 4 done) but leave settings.json empty (step 5 not done) → bootstrap skips steps 1-4, runs steps 5-6

**GitHub auth already done (bootstrap-v2.AC2.1):**
- Mock `gh auth status` returning exit 0 with username → output contains "Already connected to GitHub as"

**Azure routing (bootstrap-v2.AC2.5, AC2.7):**
- Config with `githubUser: "psford"` → step 3 runs (Azure required)
- Config with `githubUser: "other"` and `secrets.provider: "env"` → step 3 is skipped silently (no Azure output)

**Secrets skip (bootstrap-v2.AC7.2):**
- Config with `secrets.provider: "skip"` → step 6 skips cleanly with no warning

**--secrets-only flag:**
- Run with `--secrets-only` → only step 6 runs (no tool checks, no auth)

**Error handling integration:**
- Mock `check_tool` failing for `jq` → output contains "Dockerfile" (abort message from Layer 2)

**Verification:**
Run: `bash tests/test-bootstrap.sh`
Expected: All tests pass

**Commit:** `test: add bootstrap.sh orchestrator tests`

<!-- END_TASK_3 -->

<!-- START_TASK_4 -->
### Task 4: Verify full test suite passes

**Files:** None (verification only)

**Step 1: Run all tests**

Run:
```bash
bash tests/test-contracts.sh && bash tests/test-tools.sh && bash tests/test-errors.sh && bash tests/test-bootstrap.sh
```
Expected: All tests pass

**Step 2: Run shellcheck on all files**

Run:
```bash
shellcheck config/bootstrap.sh config/lib/contracts.sh config/lib/tools.sh config/lib/errors.sh
```
Expected: No errors
<!-- END_TASK_4 -->
