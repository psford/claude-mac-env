# Bootstrap v2 Design

## Summary

Bootstrap v2 is a redesign of the automated environment setup system for a Mac-based Claude Code development container. The original bootstrap broke due to compounding structural problems: Dev Container Features were trying to run GitHub and Azure authentication at Docker image build time — a context where no credentials, browser, or user interaction are available. JSON files were generated using bash string substitution, which silently produced malformed output. And there were no integration tests linking the setup phases together, so failures in one phase went undetected until the whole environment failed to stand up.

The redesign separates the system into three explicit layers with defined contracts between them. Layer 1 is a set of single-purpose tool functions that each do one job, validate their own preconditions and postconditions, and return structured output. Layer 2 is a dedicated error handling module that translates machine errors into recovery decisions (retry, skip, or abort) with plain-English user messages. Layer 3 is the orchestrator — `bootstrap.sh` — which runs as `postCreateCommand` when the container starts, chains the tools together, owns all user-facing progress messaging, and routes auth-dependent steps (GitHub login, Azure login, secrets loading) to a context where interactive terminals and browser flows are actually available. Dev Container Features are stripped back to system-level operations only. JSON generation is migrated to `jq`. CI checks structurally prevent each failure mode from recurring, and a full end-to-end integration test verifies the entire chain inside a real container build.

## Definition of Done

All 4 Dev Container Features are published to GHCR and resolvable by the Dev Containers CLI. The bootstrap is fully automated — a container rebuild on any machine with GitHub auth produces a working environment with skills, hooks, git configuration, Claude Code settings, and secrets (for psford: including Azure). No manual steps remain except interactive auth (`gh auth login`, optionally `az login`). Every component boundary has an explicit contract with a test that verifies it. The process failures that caused the original breakage (silent failures, hallucinated URLs, bash JSON generation, missing cross-phase integration tests) are structurally prevented by CI checks and contract tests.

## Acceptance Criteria

### bootstrap-v2.AC1: Features published to GHCR
- **bootstrap-v2.AC1.1 Success:** All 4 Features resolve via `docker manifest inspect ghcr.io/psford/claude-mac-env/<feature>:1.0.0`
- **bootstrap-v2.AC1.2 Success:** Dev Containers CLI can pull and install each Feature during container build
- **bootstrap-v2.AC1.3 Failure:** Publish workflow fails if Feature install.sh contains `gh auth`, `az login`, or private repo clone
- **bootstrap-v2.AC1.4 Edge:** Re-publishing same tag overwrites existing OCI image (idempotent)

### bootstrap-v2.AC2: Bootstrap authenticates user with guided flow
- **bootstrap-v2.AC2.1 Success:** If already authed (`gh auth status` exits 0), prints "✓ Already connected to GitHub as {user}" and skips
- **bootstrap-v2.AC2.2 Success:** If not authed, explains what's about to happen in plain English, runs `gh auth login --web --git-protocol https`, waits for completion
- **bootstrap-v2.AC2.3 Success:** On login failure, explains common causes (browser didn't open, network issue) and offers immediate retry
- **bootstrap-v2.AC2.4 Success:** After successful gh login, runs `gh auth setup-git` automatically (user never sees this)
- **bootstrap-v2.AC2.5 Success:** For psford, if Azure not authed, explains why Azure is needed ("Your secrets are stored in Azure Key Vault") and runs `az login`
- **bootstrap-v2.AC2.6 Edge:** Non-psford with secrets.provider == "azure" — explains Azure is needed for their secrets config, offers login or skip ("You can add this later")
- **bootstrap-v2.AC2.7 Edge:** Non-psford with secrets.provider != "azure" — no Azure mention at all
- **bootstrap-v2.AC2.8 Edge:** User cancels gh login 3 times — bootstrap exits with friendly message ("No worries — run this command when you're ready: ...")

### bootstrap-v2.AC3: Git credential helper configured (automatic, invisible to user)
- **bootstrap-v2.AC3.1 Success:** `gh auth setup-git` runs automatically after successful GitHub login — user never sees it
- **bootstrap-v2.AC3.2 Success:** `git config credential.helper` contains "gh" after Phase 2 completes
- **bootstrap-v2.AC3.3 Edge:** If `gh auth setup-git` fails, retry silently once. If still fails, warn but continue (git push may fail later, but setup doesn't block)

### bootstrap-v2.AC4: Skills installed from both repos
- **bootstrap-v2.AC4.1 Success:** ed3d-plugins skills found at `plugins/*/skills/*/SKILL.md` and copied to `~/.claude/skills/`
- **bootstrap-v2.AC4.2 Success:** psford/claude-config skills found and copied to `~/.claude/skills/`
- **bootstrap-v2.AC4.3 Success:** Postcondition check: skill count > 0 and known skill (e.g., brainstorming) exists
- **bootstrap-v2.AC4.4 Failure:** Clone fails — Layer 2 offers retry ("Couldn't reach GitHub. Check your connection and try again?")
- **bootstrap-v2.AC4.5 Failure:** Zero skills found after clone — Layer 2 returns abort with clear message naming the bad directory pattern
- **bootstrap-v2.AC4.6 Idempotent:** If skills already installed (count > 0, known skill present), prints "✓ Skills already installed" and skips

### bootstrap-v2.AC5: Claude Code hooks written to settings.json
- **bootstrap-v2.AC5.1 Success:** `~/.claude/settings.json` contains PreToolUse hook entries for commit atomicity, branch protection, force push, destructive rm
- **bootstrap-v2.AC5.2 Success:** Existing settings.json content preserved (jq merge, not overwrite)
- **bootstrap-v2.AC5.3 Failure:** Resulting settings.json is invalid JSON — Layer 2 returns abort with "settings file is corrupt"
- **bootstrap-v2.AC5.4 Edge:** settings.json doesn't exist yet — bootstrap creates it from scratch
- **bootstrap-v2.AC5.5 Idempotent:** If settings.json already has expected hook keys, prints "✓ Claude Code hooks configured" and skips

### bootstrap-v2.AC6: Symlinks and PATH fixes
- **bootstrap-v2.AC6.1 Success:** `/usr/local/bin/gh --version` exits 0 after Step 5
- **bootstrap-v2.AC6.2 Idempotent:** gh already at `/usr/local/bin/gh` — no-op, no message
- **bootstrap-v2.AC6.3 Failure:** gh not found anywhere — Layer 2 returns skip, non-critical

### bootstrap-v2.AC7: Secrets loaded
- **bootstrap-v2.AC7.1 Success:** `~/.secrets.env` exists and is non-empty (when provider configured)
- **bootstrap-v2.AC7.2 Edge:** secrets.provider == "skip" — Step 6 skips cleanly, no warning
- **bootstrap-v2.AC7.3 Failure:** Provider error — Layer 2 returns skip with friendly message ("Secrets couldn't load. Your environment will work, but some features need credentials. Run `bootstrap.sh --secrets-only` to try again later.")
- **bootstrap-v2.AC7.4 Idempotent:** If ~/.secrets.env exists and is recent, prints "✓ Secrets loaded" and skips

### bootstrap-v2.AC8: Bootstrap is idempotent and recoverable
- **bootstrap-v2.AC8.1 Success:** Re-running bootstrap after successful completion produces no errors and no re-prompts
- **bootstrap-v2.AC8.2 Success:** Killing bootstrap mid-run and re-running resumes from the first incomplete step
- **bootstrap-v2.AC8.3 Success:** Each step independently detects whether its work is already done
- **bootstrap-v2.AC8.4 Edge:** User re-runs setup.sh from scratch — project directories and config from .user-config.json are preserved, not re-prompted

### bootstrap-v2.AC9: JSON generation uses jq
- **bootstrap-v2.AC9.1 Success:** `render_devcontainer()` uses only `jq` for JSON manipulation
- **bootstrap-v2.AC9.2 Success:** `jq . < .devcontainer/devcontainer.json` exits 0 after every render
- **bootstrap-v2.AC9.3 Failure:** No `sed`, `awk`, or bash variable substitution operates on JSON content in setup.sh

### bootstrap-v2.AC10: CI enforces contracts
- **bootstrap-v2.AC10.1 Success:** CI fails if Feature install.sh contains forbidden auth commands
- **bootstrap-v2.AC10.2 Success:** CI fails if rendered devcontainer.json is invalid JSON
- **bootstrap-v2.AC10.3 Success:** CI fails if hardcoded repo URLs don't resolve via `gh repo view`
- **bootstrap-v2.AC10.4 Success:** Post-publish CI verifies all GHCR Feature manifests exist

### bootstrap-v2.AC11: E2E integration test
- **bootstrap-v2.AC11.1 Success:** CI builds full container from generated devcontainer.json
- **bootstrap-v2.AC11.2 Success:** Bootstrap runs inside container and all postconditions pass (skills > 0, settings.json valid, hooks installed, credential helper set)
- **bootstrap-v2.AC11.3 Failure:** E2E job fails if any bootstrap postcondition is unmet

### bootstrap-v2.AC12: Pre-commit hook non-interactive support
- **bootstrap-v2.AC12.1 Success:** Hook exits 0 when stdin is not a TTY (e.g., Claude Code, CI)
- **bootstrap-v2.AC12.2 Success:** Hook still prompts when stdin is a TTY (interactive terminal)
- **bootstrap-v2.AC12.3 Edge:** `CLAUDE_CODE=1` env var bypasses prompt regardless of TTY state

## Glossary

- **Dev Container Feature**: A reusable, self-contained add-on unit for VS Code Dev Containers. Each Feature has an `install.sh` that runs during Docker image build, with no user session, no mounted volumes, and no network credentials available.
- **postCreateCommand**: A Dev Container lifecycle hook that runs after the container is created and started, in an interactive terminal with the user's workspace mounted. This is where auth flows and user-specific setup belong.
- **GHCR (GitHub Container Registry)**: GitHub's OCI-compatible container and artifact registry, used here to host published Dev Container Features as OCI images at `ghcr.io/psford/claude-mac-env/*`.
- **OCI image**: An image conforming to the Open Container Initiative specification — the standard format for Docker images and Dev Container Features pushed to registries like GHCR.
- **jq**: A command-line JSON processor used here to safely generate and merge JSON files, replacing fragile bash string substitution.
- **Design-by-contract**: A programming discipline where each function declares explicit preconditions (what must be true before it runs), postconditions (what must be true after), and invariants (what must remain true throughout). Violations fail loudly.
- **Layer 1 / Layer 2 / Layer 3**: The three-tier architecture defined in this design. Layer 1 = single-purpose tool functions; Layer 2 = error handling and recovery policy; Layer 3 = orchestration, UX, and user flow.
- **Idempotent**: An operation that produces the same result whether run once or many times. Each bootstrap step checks whether its work is already done and skips cleanly if so.
- **Credential helper**: A git subsystem (`git config credential.helper`) that supplies authentication tokens to git commands. Configured here by `gh auth setup-git` so that `git push` works without re-prompting.
- **Secrets provider plugin**: The existing architecture in `config/secrets-interface.sh` and `config/secrets-*.sh` that abstracts where secrets come from. Each provider implements a three-function interface: `secrets_validate`, `secrets_inject`, `secrets_describe`.
- **Identity routing**: The pattern of branching behavior based on the authenticated GitHub username — primarily to auto-enable all features and require Azure auth for the `psford` identity.
- **Validation chain**: Named `validate_chain_*()` functions that collect all errors before reporting, rather than aborting on the first failure.
- **TTY**: A connected interactive terminal. Used here to detect whether a script is running in an interactive user session (where prompts make sense) vs. in CI or Claude Code (where prompts would hang).
- **Brother-in-law test**: Informal usability standard — error messages should be understandable to a non-technical person, with plain English and actionable next steps.

## Architecture

### Layered Design

Three layers, each with distinct responsibilities:

```
┌─────────────────────────────────────────────────────┐
│ Layer 3: ORCHESTRATION (bootstrap.sh, setup.sh)     │
│   Chains tools together. Owns UX — progress,        │
│   plain English, step numbering. Facilitates auth.   │
│   Idempotent: detects prior work, skips completed    │
│   steps. If killed and re-run, recovers gracefully.  │
│   Contains NO business logic, NO error recovery.     │
├─────────────────────────────────────────────────────┤
│ Layer 2: ERROR HANDLING (lib/errors.sh)              │
│   Accepts structured errors from Layer 1 tools.      │
│   Knows retry policy per error type. Translates      │
│   machine errors into human-readable guidance.        │
│   Returns: retry | skip | abort + user message.      │
│   Contains NO UX flow, NO tool logic.                │
├─────────────────────────────────────────────────────┤
│ Layer 1: TOOLS (config/lib/*.sh)                     │
│   Design-by-contract. One function, one job.         │
│   Structured output: exit code + stdout (result)     │
│   + stderr (error details). Reusable across          │
│   projects. No UX. No retries. No friendly messages. │
└─────────────────────────────────────────────────────┘
```

**Layer 1 — Tools** (`config/lib/`): Each tool does one thing. Validates preconditions, does its work, verifies postconditions. Returns structured results: exit 0 + stdout for success, exit 1 + stderr with error type and detail for failure. Reusable, testable, movable between projects. Examples: `check_gh_auth`, `clone_skills_repo`, `merge_settings_json`, `render_devcontainer_json`.

**Layer 2 — Error Handling** (`config/lib/errors.sh`): Accepts error output from Layer 1. Has a contract: given an error type and detail, returns a recovery action (retry/skip/abort) and a human-readable message. Knows that `gh_auth_failed` means "offer retry with explanation about browser OAuth" while `missing_tool` means "abort — Dockerfile is broken." Does not know about UX flow or step ordering.

**Layer 3 — Orchestration** (`config/bootstrap.sh`, `setup.sh`): Calls Layer 1 tools. On failure, passes the error to Layer 2 and acts on the response — retry the tool, skip and continue, or abort with the human message. Owns all UX: "Step 2 of 6: Connecting to GitHub...", "✓ Already connected as psford", progress indicators. Idempotent: each step checks if its work is already done before acting.

### Execution Contexts

| Context | When | Auth | Filesystem | Layer |
|---------|------|------|------------|-------|
| Feature install.sh | Image build | None | No mounts, no workspace | Layer 1 only (system-level tools) |
| postCreateCommand | Container start | Interactive TTY available | Mounts available, workspace present | All 3 layers |
| setup.sh | Mac host, before container | Interactive TTY | Host filesystem | All 3 layers |

Features prepare filesystem structure at build time (Layer 1 only — no auth, no UX). Bootstrap populates it at container start with all three layers active.

### Component Overview

```
┌─────────────────────────────────────────────────────┐
│ publish-features.yml (CI)                           │
│   v* tag → devcontainers/action → GHCR OCI publish  │
│   post-publish: verify each manifest resolves        │
└──────────────┬──────────────────────────────────────┘
               │ publishes
               ▼
┌─────────────────────────────────────────────────────┐
│ GHCR (ghcr.io/psford/claude-mac-env/*)              │
│   claude-skills:1.0.0    universal-hooks:1.0.0      │
│   csharp-tools:1.0.0     psford-personal:1.0.0     │
└──────────────┬──────────────────────────────────────┘
               │ referenced by
               ▼
┌─────────────────────────────────────────────────────┐
│ devcontainer.json (generated by setup.sh via jq)     │
│   features: { "ghcr.io/.../claude-skills:1": {} }   │
│   postCreateCommand: config/bootstrap.sh             │
└──────────┬──────────────┬───────────────────────────┘
           │              │
     build time      container start
           │              │
           ▼              ▼
┌──────────────┐  ┌───────────────────────────────────┐
│ Features     │  │ bootstrap.sh (Layer 3)             │
│ (Layer 1)    │  │  calls Layer 1 tools               │
│  - mkdir     │  │  errors → Layer 2 → retry/skip     │
│  - copy      │  │  UX: progress, plain English       │
│  - apt-get   │  │  idempotent: skips completed work  │
└──────────────┘  └───────────────────────────────────┘
```

### Bootstrap Steps

Six steps, presented to the user as a guided flow. Each step is idempotent — if already done, prints "✓" and moves on. If the user kills the process and re-runs, it picks up where it left off.

```
Step 1 of 6: Checking tools
  Layer 1: check_tool() for each of git, curl, jq, node, python3, claude
  idempotent: always runs (fast, no side effects)
  on error: Layer 2 returns abort — "These tools should be in the
            container image. Something is wrong with the Dockerfile."

Step 2 of 6: Connecting to GitHub
  Layer 1: check_gh_auth() — returns authed/not-authed/error
  idempotent: if authed, print "✓ Already connected as {user}"
  if not authed: Layer 3 explains what's about to happen, runs
    gh auth login --web --git-protocol https
  then: run_gh_setup_git() — configures credential helper
  on error: Layer 2 returns retry — "That didn't work. Common
            reasons: browser didn't open, network issue. Try again?"
  after 3 retries: Layer 2 returns abort — friendly exit message
            with the exact command to run later

Step 3 of 6: Connecting to Azure (conditional)
  Layer 1: check_az_auth() — returns authed/not-authed/error
  shown if: psford (always) or secrets.provider == "azure" (prompted)
  idempotent: if authed, print "✓ Already connected to Azure"
  if not authed (psford): explain why, run az login
  if not authed (other): "Azure Key Vault requires login. Connect
    now, or skip and add later? [Connect / Skip]"
  on error: Layer 2 returns retry or skip depending on identity

Step 4 of 6: Installing skills
  Layer 1: clone_skills_repo() for each repo, install_skills()
  idempotent: if ~/.claude/skills/ already has skills, check count
    and known skill names — skip if already populated
  on error: Layer 2 returns retry — "Couldn't reach GitHub. Check
    your connection and try again?"

Step 5 of 6: Configuring Claude Code
  Layer 1: merge_settings_json() — reads existing, merges hooks, validates
  Layer 1: fix_symlinks() — gh to /usr/local/bin if needed
  idempotent: if settings.json already has expected keys, skip merge.
    if symlink exists, skip.
  on error (settings): Layer 2 returns abort — settings.json is corrupt
  on error (symlink): Layer 2 returns skip — non-critical

Step 6 of 6: Loading secrets
  Layer 1: existing secrets provider architecture (unchanged)
  idempotent: if ~/.secrets.env exists and is recent, skip
  on error: Layer 2 returns skip — "Secrets couldn't load. Your
    environment will work, but some features need credentials.
    You can run 'bootstrap.sh --secrets-only' to try again later."
```

### Identity Routing

Follows existing pattern in `setup.sh` (line 945):

```
if githubUser == "psford":
  all features enabled
  Azure auth: facilitated in Step 3, required
else:
  tiered feature selection (existing flow)
  Azure auth: offered in Step 3 only if secrets.provider == "azure"
```

### JSON Generation

`render_devcontainer()` in `setup.sh` switches from bash string replacement to `jq`. The template becomes a valid JSON base file. `jq` merges in features, mounts, and extensions. Postcondition: `jq . < devcontainer.json` exits 0 after every render.

## Existing Patterns

**Validation chains** (`config/validate-dependencies.sh`): Named `validate_chain_*()` functions that collect errors without aborting early, using global `VALIDATION_ERRORS` / `VALIDATION_WARNINGS` counters. Bootstrap.sh reuses this pattern — each phase is a validation chain that reports all failures before exiting.

**Secrets provider plugin** (`config/secrets-interface.sh` + `config/secrets-*.sh`): Three-function interface (`secrets_validate`, `secrets_inject`, `secrets_describe`), discovered via config, sourced dynamically, interface validated before use. Bootstrap Phase 7 continues to use this architecture unchanged.

**Identity routing** (`setup.sh:945`): GitHub username from `.user-config.json` matched against `"psford"` to auto-select features. Extended to also control auth requirements in bootstrap.

**Feature install pattern** (`features/*/install.sh`): Dependency checks at top, core logic, ownership fixup, verification report. Preserved but stripped of auth-dependent operations.

## Implementation Phases

<!-- START_PHASE_1 -->
### Phase 1: Strip Auth from Features and Publish to GHCR

**Goal:** Make all 4 Features publishable and publish them as OCI images to GHCR.

**Components:**
- `features/claude-skills/install.sh` — remove gh auth check, remove repo clones, keep only directory creation (`~/.claude/skills/`) and ownership fixup
- `.github/workflows/publish-features.yml` — add post-publish verification step that runs `docker manifest inspect` on each published Feature

**Dependencies:** None (first phase)

**Done when:**
- `v1.0.0` tag pushed, workflow succeeds
- All 4 Features resolvable at `ghcr.io/psford/claude-mac-env/<feature>:1.0.0`
- `claude-skills/install.sh` contains no auth-dependent commands
- bootstrap-v2.AC1.*
<!-- END_PHASE_1 -->

<!-- START_PHASE_2 -->
### Phase 2: Layer 1 Tools

**Goal:** Build the design-by-contract tool functions that do the actual work. Each tool has preconditions, does one thing, verifies postconditions, returns structured results. No UX, no retries.

**Components:**
- `config/lib/tools.sh` — Layer 1 tool functions:
  - `check_tool(cmd)` — verifies a CLI tool exists and responds to --version
  - `check_gh_auth()` — returns authed (with username) / not-authed / error
  - `check_az_auth()` — returns authed / not-authed / error
  - `run_gh_login()` — runs `gh auth login --web --git-protocol https`, returns success/failure
  - `run_gh_setup_git()` — runs `gh auth setup-git`, verifies credential.helper set
  - `run_az_login()` — runs `az login`, returns success/failure
  - `clone_skills_repo(url, name)` — clones repo to temp dir, returns path or error
  - `install_skills(source_dir, target_dir)` — finds `plugins/*/skills/*/SKILL.md`, copies, returns count
  - `merge_settings_json(config_fragment, target_path)` — jq merge, validates output
  - `fix_symlink(source, target)` — creates symlink if needed, verifies
  - `load_secrets(provider, config_path)` — runs existing provider architecture
- `config/lib/contracts.sh` — shared precondition/postcondition check helpers
- Tests for each tool function in isolation — contract tests verifying pre/postconditions

**Dependencies:** Phase 1 (Features published, container can build)

**Done when:**
- Each tool function passes its contract tests in isolation
- Tools return structured output (exit code + stdout/stderr) not human messages
- bootstrap-v2.AC2.1, AC3.*, AC4.1-AC4.3, AC5.1-AC5.2, AC6.1-AC6.2, AC7.1
<!-- END_PHASE_2 -->

<!-- START_PHASE_3 -->
### Phase 3: Layer 2 Error Handling

**Goal:** Build the error handling layer that accepts structured errors from Layer 1 and returns recovery actions + human-readable messages.

**Components:**
- `config/lib/errors.sh` — error handler functions:
  - `handle_error(error_type, detail, context)` — dispatches to specific handler, returns action (retry/skip/abort) + user message
  - Error type handlers: `handle_auth_error`, `handle_clone_error`, `handle_json_error`, `handle_tool_missing`
  - Retry policy per error type (e.g., auth: 3 retries, clone: 2 retries, tool missing: 0 retries)
  - Human message templates — plain English, no jargon, actionable
- Tests for each error handler — given error type X, returns action Y with message Z

**Dependencies:** Phase 2 (Layer 1 tools define the error shapes)

**Done when:**
- Each error type maps to a specific recovery action
- Messages are plain English and actionable (brother-in-law test)
- bootstrap-v2.AC2.3, AC2.8, AC4.4, AC5.3, AC6.3, AC7.3
<!-- END_PHASE_3 -->

<!-- START_PHASE_4 -->
### Phase 4: Layer 3 Orchestration — bootstrap.sh

**Goal:** Build the orchestration layer that chains tools, handles errors, guides the user through the 6-step flow. Idempotent.

**Components:**
- `config/bootstrap.sh` — Layer 3 orchestrator:
  - Sources `config/lib/tools.sh`, `config/lib/errors.sh`
  - 6-step flow with progress indicators ("Step 2 of 6: Connecting to GitHub...")
  - Each step: check if already done → if yes, "✓" and skip → if no, call Layer 1 tool → on error, call Layer 2 handler → act on response (retry/skip/abort)
  - Identity routing: reads githubUser from `.user-config.json`, controls Azure behavior
  - `--secrets-only` flag for re-running just the secrets step
- `.devcontainer/devcontainer.json.template` — update postCreateCommand to `config/bootstrap.sh`
- `config/bootstrap-secrets.sh` — refactored into Layer 1 function callable from bootstrap.sh

**Dependencies:** Phase 3 (error handling layer ready)

**Done when:**
- Full bootstrap runs end-to-end with guided UX
- Each step is idempotent — re-run skips completed work
- Killed mid-run and re-run: resumes from first incomplete step
- bootstrap-v2.AC2.*, AC4.6, AC5.5, AC7.2, AC7.4, AC8.*
<!-- END_PHASE_4 -->

<!-- START_PHASE_5 -->
### Phase 5: Replace Bash JSON with jq in setup.sh

**Goal:** Eliminate bash string replacement for JSON generation, removing an entire class of bugs.

**Components:**
- `setup.sh` — rewrite `render_devcontainer()` using Layer 1 tool `render_devcontainer_json()` from `config/lib/tools.sh`
- `.devcontainer/devcontainer.json.template` — convert from placeholder-based template to valid JSON base file that `jq` can read and modify
- Postcondition: `jq . < .devcontainer/devcontainer.json` runs after every render

**Dependencies:** Phase 2 (Layer 1 tools available)

**Done when:**
- `render_devcontainer()` uses only `jq` for JSON manipulation
- No `sed`, `awk`, or bash string replacement used on JSON content
- Generated `devcontainer.json` passes `jq .` validation
- bootstrap-v2.AC9.*
<!-- END_PHASE_5 -->

<!-- START_PHASE_6 -->
### Phase 6: CI Contract Enforcement

**Goal:** Add CI checks that structurally prevent the failure modes from recurring.

**Components:**
- `.github/workflows/ci.yml` — add jobs:
  - Static analysis: grep Feature install.sh for forbidden auth commands
  - JSON validation: render devcontainer.json with test config, validate with `jq .`
  - External ref validation: `validate_chain_external_refs()` checks all hardcoded repo URLs with `gh repo view`
- `.github/workflows/publish-features.yml` — add post-publish manifest verification
- `config/validate-dependencies.sh` — add `validate_chain_external_refs()` function

**Dependencies:** Phase 5 (jq rendering in place)

**Done when:**
- CI fails if Feature install.sh contains auth commands
- CI fails if rendered devcontainer.json is invalid JSON
- CI fails if hardcoded repo URLs don't resolve
- Post-publish CI verifies all GHCR manifests exist
- bootstrap-v2.AC10.*
<!-- END_PHASE_6 -->

<!-- START_PHASE_7 -->
### Phase 7: E2E Integration Test and Non-Interactive Hook Fix

**Goal:** Full container build + bootstrap test, and fix pre-commit hook for Claude Code.

**Components:**
- `.github/workflows/ci.yml` — add E2E job: build container from generated devcontainer.json, run bootstrap.sh with mock auth, verify postconditions (skills count, settings.json valid, hooks installed, credential helper configured)
- `features/universal-hooks/hooks/pre-commit-permission.sh` — detect non-TTY (`! [ -t 0 ]`) or `CLAUDE_CODE=1` env var, skip interactive prompt
- `scripts/test-e2e-bootstrap.sh` — orchestrates the E2E verification, checking each bootstrap postcondition

**Dependencies:** Phase 6 (CI infrastructure in place)

**Done when:**
- E2E CI job passes: container builds, bootstrap runs, all postconditions verified
- Pre-commit hook allows non-interactive commits (Claude Code, CI)
- bootstrap-v2.AC11.*, AC12.*
<!-- END_PHASE_7 -->

## Additional Considerations

**Auth happens at container start, not before.** `postCreateCommand` runs in an interactive terminal. `gh auth login` and `az login` work here — the bootstrap facilitates login directly rather than requiring users to pre-authenticate. This is the key UX difference from v1.

**Feature versioning:** Initial publish is `v1.0.0`. Subsequent changes to Feature install.sh require a new tag. The publish workflow triggers on any `v*` tag. Consider adopting semver: patch for bug fixes, minor for new optional behavior, major for breaking changes to Feature contracts.

**Backward compatibility:** `bootstrap-secrets.sh` is refactored into Layer 1 functions within bootstrap.sh. Any external references to `bootstrap-secrets.sh` (e.g., existing containers with old devcontainer.json) will break. This is acceptable — the project is pre-release and has one user.
