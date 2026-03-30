# Bootstrap v2 Test Requirements

Maps every acceptance criterion (AC1-AC12) to specific tests. Cross-referenced against implementation phases 1-7 to ensure full coverage.

## Legend

- **Unit**: Tests a single function in isolation with mocks
- **Integration**: Tests multiple components working together
- **E2E**: Full container build + bootstrap run + postcondition verification
- **CI**: Enforced by GitHub Actions workflow job
- **Static**: grep/shellcheck analysis of source files

---

## AC1: Features published to GHCR

| AC ID | Description | Test Type | Test File | Automated? | Notes |
|-------|-------------|-----------|-----------|------------|-------|
| AC1.1 | All 4 Features resolve via `docker manifest inspect` | CI | `.github/workflows/publish-features.yml` (verify job) | Yes | Post-publish job runs `docker manifest inspect` on each of claude-skills, universal-hooks, csharp-tools, psford-personal. Phase 1 Task 2. |
| AC1.2 | Dev Containers CLI can pull and install each Feature during container build | E2E | `.github/workflows/ci.yml` (e2e job) | Yes | E2E job builds full container from generated devcontainer.json with Features referenced. Phase 7 Task 3. |
| AC1.3 | Publish workflow fails if Feature install.sh contains `gh auth`, `az login`, or private repo clone | CI + Static | `.github/workflows/ci.yml` (feature-guard job) | Yes | Greps all `features/*/install.sh` for forbidden patterns. Phase 1 Task 3. |
| AC1.4 | Re-publishing same tag overwrites existing OCI image (idempotent) | Human | N/A | No | Requires pushing the same v-tag twice to GHCR and verifying the manifest is updated. This is a property of the OCI registry, not application code. **Verification:** Manually push tag, re-push, verify manifest digest changes. One-time verification during initial publish. |

## AC2: Bootstrap authenticates user with guided flow

| AC ID | Description | Test Type | Test File | Automated? | Notes |
|-------|-------------|-----------|-----------|------------|-------|
| AC2.1 | Already authed: prints "Already connected to GitHub as {user}" and skips | Unit + Integration | `tests/test-tools.sh`, `tests/test-bootstrap.sh` | Yes | `test-tools.sh`: mock `gh auth status` exit 0 returns `authed:<user>`. `test-bootstrap.sh`: mock gh authed, verify output contains "Already connected to GitHub as". Phase 2 Task 4, Phase 4 Task 3. |
| AC2.2 | Not authed: explains in plain English, runs `gh auth login --web --git-protocol https` | Human | N/A | No | Interactive browser OAuth flow cannot be automated in CI. **Verification:** Manual test in fresh container with no gh auth. Verify: (1) explanation message appears before prompt, (2) `gh auth login --web --git-protocol https` is the exact command run, (3) flow waits for completion. |
| AC2.3 | On login failure: explains common causes, offers retry | Unit | `tests/test-errors.sh` | Yes | Verifies `handle_error gh_login_failed` returns `retry:` with message containing browser/network explanation. Phase 3 Task 2. |
| AC2.4 | After successful login, runs `gh auth setup-git` automatically | Unit | `tests/test-tools.sh` | Yes | `run_gh_setup_git` mock test verifies it runs and checks postcondition (`git config credential.helper` contains "gh"). Phase 2 Task 4. |
| AC2.5 | For psford, if Azure not authed, explains why and runs `az login` | Integration | `tests/test-bootstrap.sh` | Yes | Config with `githubUser: "psford"` triggers step 3 (Azure required). Phase 4 Task 3. |
| AC2.6 | Non-psford with secrets.provider == "azure": offers login or skip | Human | N/A | No | Requires interactive terminal to verify the offer/skip prompt UX. **Verification:** Manual test with non-psford config and `secrets.provider: "azure"`. Verify prompt appears with skip option. |
| AC2.7 | Non-psford with secrets.provider != "azure": no Azure mention | Integration | `tests/test-bootstrap.sh` | Yes | Config with `githubUser: "other"` and `secrets.provider: "env"` produces no Azure output. Phase 4 Task 3. |
| AC2.8 | User cancels gh login 3 times: exits with friendly message | Unit | `tests/test-errors.sh` | Yes | Calls `handle_error gh_login_failed` 4 times. First 3 return `retry:`, fourth returns `abort:` with message containing "No worries". Phase 3 Task 2. |

## AC3: Git credential helper configured

| AC ID | Description | Test Type | Test File | Automated? | Notes |
|-------|-------------|-----------|-----------|------------|-------|
| AC3.1 | `gh auth setup-git` runs automatically after successful GitHub login | Unit | `tests/test-tools.sh` | Yes | `run_gh_setup_git` mock verifies execution. Orchestration test in `test-bootstrap.sh` verifies it is called after auth success. Phase 2 Task 4. |
| AC3.2 | `git config credential.helper` contains "gh" after Phase 2 | Unit + E2E | `tests/test-tools.sh`, `scripts/test-e2e-bootstrap.sh` | Yes | Unit: postcondition check in `run_gh_setup_git`. E2E: postcondition check #5 verifies credential helper is set. Phase 2 Task 4, Phase 7 Task 2. |
| AC3.3 | If `gh auth setup-git` fails, retry once then warn and continue | Unit | `tests/test-errors.sh` | Yes | `handle_error gh_setup_git_failed` returns `retry:` on first call, `skip:` on second. Phase 3 Task 1. |

## AC4: Skills installed from both repos

| AC ID | Description | Test Type | Test File | Automated? | Notes |
|-------|-------------|-----------|-----------|------------|-------|
| AC4.1 | ed3d-plugins skills found at `plugins/*/skills/*/SKILL.md` and copied | Unit | `tests/test-tools.sh` | Yes | Creates source dir with expected structure, calls `install_skills`, verifies count > 0. Phase 2 Task 4. |
| AC4.2 | psford/claude-config skills found and copied | Unit | `tests/test-tools.sh` | Yes | Same pattern as AC4.1 with second repo structure. Phase 2 Task 4. |
| AC4.3 | Postcondition: skill count > 0, known skill (brainstorming) exists | Unit + E2E | `tests/test-tools.sh`, `scripts/test-e2e-bootstrap.sh` | Yes | Unit: verifies brainstorming skill directory exists in target after install. E2E: checks #1 and #2 verify skills count and brainstorming presence. Phase 2 Task 4, Phase 7 Task 2. |
| AC4.4 | Clone fails: Layer 2 offers retry | Unit | `tests/test-errors.sh` | Yes | `handle_error clone_failed` returns `retry:` with message containing "Couldn't reach GitHub". Phase 3 Task 2. |
| AC4.5 | Zero skills found after clone: Layer 2 returns abort | Unit | `tests/test-errors.sh` | Yes | `handle_error no_skills_found` returns `abort:` with message naming the bad directory pattern. Phase 3 Task 2. |
| AC4.6 | Idempotent: skills already installed, prints skip and moves on | Integration | `tests/test-bootstrap.sh` | Yes | Pre-populates `~/.claude/skills/brainstorming/SKILL.md`, verifies step 4 prints "already installed". Phase 4 Task 3. |

## AC5: Claude Code hooks written to settings.json

| AC ID | Description | Test Type | Test File | Automated? | Notes |
|-------|-------------|-----------|-----------|------------|-------|
| AC5.1 | settings.json contains PreToolUse hook entries | Unit + E2E | `tests/test-tools.sh`, `scripts/test-e2e-bootstrap.sh` | Yes | Unit: `merge_settings_json` creates file with hooks. E2E: check #4 verifies PreToolUse entries exist. Phase 2 Task 4, Phase 7 Task 2. |
| AC5.2 | Existing settings.json content preserved (jq merge) | Unit | `tests/test-tools.sh` | Yes | Merge into existing target verifies existing keys preserved and new ones added. Phase 2 Task 4. |
| AC5.3 | Invalid JSON result: Layer 2 returns abort with "corrupt" | Unit | `tests/test-errors.sh` | Yes | `handle_error json_merge_failed` returns `abort:` with message containing "corrupt". Phase 3 Task 2. |
| AC5.4 | settings.json doesn't exist yet: bootstrap creates from scratch | Unit + Integration | `tests/test-tools.sh`, `tests/test-bootstrap.sh` | Yes | Unit: `merge_settings_json` into non-existent target creates new file. Integration: bootstrap step 5 creates settings.json when absent. Phase 2 Task 4, Phase 4 Task 3. |
| AC5.5 | Idempotent: already has hooks, prints skip | Integration | `tests/test-bootstrap.sh` | Yes | Pre-populates settings.json with expected hook keys, verifies step 5 prints "hooks configured". Phase 4 Task 3. |

## AC6: Symlinks and PATH fixes

| AC ID | Description | Test Type | Test File | Automated? | Notes |
|-------|-------------|-----------|-----------|------------|-------|
| AC6.1 | `/usr/local/bin/gh --version` exits 0 | Unit + E2E | `tests/test-tools.sh`, `scripts/test-e2e-bootstrap.sh` | Yes | Unit: `fix_symlink` creates symlink, postcondition verified. E2E: check #6 verifies `which gh` returns a path. Phase 2 Task 4, Phase 7 Task 2. |
| AC6.2 | gh already at correct path: no-op | Unit | `tests/test-tools.sh` | Yes | Source exists, target already correct: returns 0 with no changes. Phase 2 Task 4. |
| AC6.3 | gh not found anywhere: Layer 2 returns skip | Unit | `tests/test-errors.sh` | Yes | `handle_error symlink_failed` returns `skip:` (non-critical). Phase 3 Task 2. |

## AC7: Secrets loaded

| AC ID | Description | Test Type | Test File | Automated? | Notes |
|-------|-------------|-----------|-----------|------------|-------|
| AC7.1 | `~/.secrets.env` exists and is non-empty when provider configured | Unit | `tests/test-tools.sh` | Yes | Mock secrets provider returning success, verify `load_secrets` returns 0. Phase 2 Task 4. |
| AC7.2 | secrets.provider == "skip": Step 6 skips cleanly, no warning | Integration | `tests/test-bootstrap.sh` | Yes | Config with `secrets.provider: "skip"`, verify step 6 skips with no warning output. Phase 4 Task 3. |
| AC7.3 | Provider error: Layer 2 returns skip with friendly message | Unit | `tests/test-errors.sh` | Yes | `handle_error secrets_failed` returns `skip:` with message containing "Secrets couldn't load". Phase 3 Task 2. |
| AC7.4 | Idempotent: secrets.env exists and recent, prints skip | Integration | `tests/test-bootstrap.sh` | Yes | Pre-populates `~/.secrets.env` (recent), verifies step 6 prints "Secrets loaded". Phase 4 Task 3. |

## AC8: Bootstrap is idempotent and recoverable

| AC ID | Description | Test Type | Test File | Automated? | Notes |
|-------|-------------|-----------|-----------|------------|-------|
| AC8.1 | Re-running after success: no errors, no re-prompts | Integration + E2E | `tests/test-bootstrap.sh`, `scripts/test-e2e-bootstrap.sh` | Yes | Integration: pre-populate all outputs, verify all steps print skip messages. E2E: check #7 runs bootstrap twice, second run produces no errors. Phase 4 Task 3, Phase 7 Task 2. |
| AC8.2 | Kill mid-run, re-run: resumes from first incomplete step | Integration | `tests/test-bootstrap.sh` | Yes | Pre-populate skills (step 4 done) but leave settings.json empty (step 5 not done), verify bootstrap skips 1-4 and runs 5-6. Phase 4 Task 3. |
| AC8.3 | Each step independently detects whether its work is done | Integration | `tests/test-bootstrap.sh` | Yes | Each step tested independently for idempotency detection. Phase 4 Task 3. |
| AC8.4 | Re-run setup.sh: .user-config.json preserved, not re-prompted | Human | N/A | No | Requires interactive `setup.sh` execution with existing `.user-config.json`. **Verification:** Manually run `setup.sh` twice with existing config. Verify second run detects existing config and does not re-prompt for project directories or GitHub user. |

## AC9: JSON generation uses jq

| AC ID | Description | Test Type | Test File | Automated? | Notes |
|-------|-------------|-----------|-----------|------------|-------|
| AC9.1 | `render_devcontainer()` uses only jq for JSON manipulation | Unit + Static | `tests/test-render-devcontainer.sh` | Yes | Calls `render_devcontainer_json`, verifies output is valid JSON with correct features/mounts/base image. Phase 5 Task 4. |
| AC9.2 | `jq . < devcontainer.json` exits 0 after every render | Unit + CI | `tests/test-render-devcontainer.sh`, `.github/workflows/ci.yml` (json-validate job) | Yes | Unit: every test render validated with `jq .`. CI: json-validate job renders with test config and validates. Phase 5 Task 4, Phase 6 Task 1. |
| AC9.3 | No `sed`, `awk`, or bash variable substitution on JSON in setup.sh | Static | `tests/test-render-devcontainer.sh` | Yes | Grep for `{{` placeholders and `rendered=.*{rendered//` patterns in setup.sh, verify zero matches. Phase 5 Task 4. |

## AC10: CI enforces contracts

| AC ID | Description | Test Type | Test File | Automated? | Notes |
|-------|-------------|-----------|-----------|------------|-------|
| AC10.1 | CI fails if Feature install.sh contains forbidden auth commands | CI | `.github/workflows/ci.yml` (feature-guard job) | Yes | Greps for `gh auth`, `az login`, `GITHUB_TOKEN`, `git clone` in all Feature install.sh files. Phase 1 Task 3. |
| AC10.2 | CI fails if rendered devcontainer.json is invalid JSON | CI | `.github/workflows/ci.yml` (json-validate job) | Yes | Renders with test config, validates with `jq .`. Phase 6 Task 1. |
| AC10.3 | CI fails if hardcoded repo URLs don't resolve via `gh repo view` | CI + Unit | `.github/workflows/ci.yml` (external-refs job), `tests/test-validate-external-refs.sh` | Yes | CI job runs `validate_chain_external_refs()`. Unit test mocks `gh repo view` for valid/invalid refs. Phase 6 Tasks 2-3, Task 5. |
| AC10.4 | Post-publish CI verifies all GHCR Feature manifests exist | CI | `.github/workflows/publish-features.yml` (verify job) | Yes | Runs `docker manifest inspect` on all 4 Features after publish. Phase 1 Task 2. |

## AC11: E2E integration test

| AC ID | Description | Test Type | Test File | Automated? | Notes |
|-------|-------------|-----------|-----------|------------|-------|
| AC11.1 | CI builds full container from generated devcontainer.json | E2E | `.github/workflows/ci.yml` (e2e job) | Yes | `docker build` from rendered devcontainer.json. Phase 7 Task 3. |
| AC11.2 | Bootstrap runs inside container, all postconditions pass | E2E | `scripts/test-e2e-bootstrap.sh`, `.github/workflows/ci.yml` (e2e job) | Yes | Runs bootstrap.sh with `BOOTSTRAP_MOCK_AUTH=1`, then verifies: skills > 0, brainstorming present, settings.json valid, hooks installed, credential helper non-empty, gh accessible, second bootstrap run clean. Phase 7 Tasks 2-3. |
| AC11.3 | E2E job fails if any postcondition unmet | E2E | `scripts/test-e2e-bootstrap.sh` | Yes | Script exits 1 if any check fails, which fails the CI job. Phase 7 Task 2. |

## AC12: Pre-commit hook non-interactive support

| AC ID | Description | Test Type | Test File | Automated? | Notes |
|-------|-------------|-----------|-----------|------------|-------|
| AC12.1 | Hook exits 0 when stdin is not a TTY | Unit | `tests/test-pre-commit-hook.sh` | Yes | Pipes input to hook: `echo "" \| bash pre-commit-permission.sh` verifies exit 0. Phase 7 Task 4. |
| AC12.2 | Hook still prompts when stdin is a TTY (interactive terminal) | Human | N/A | No | Verifying an interactive prompt requires a real TTY. **Verification:** In an interactive terminal, run `bash features/universal-hooks/hooks/pre-commit-permission.sh` and verify it reaches the `read` prompt. |
| AC12.3 | `CLAUDE_CODE=1` env var bypasses prompt regardless of TTY state | Unit | `tests/test-pre-commit-hook.sh` | Yes | `CLAUDE_CODE=1 bash pre-commit-permission.sh < /dev/null` exits 0. Also verifies `CLAUDE_CODE=0` does NOT bypass, and unset `CLAUDE_CODE` does NOT bypass. Phase 7 Task 4. |

---

## Summary

| Category | Total Criteria | Automated | Human Verification |
|----------|---------------|-----------|--------------------|
| AC1: Features published | 4 | 3 | 1 (AC1.4 — OCI idempotent republish) |
| AC2: Auth flow | 8 | 6 | 2 (AC2.2 — interactive OAuth, AC2.6 — interactive Azure offer) |
| AC3: Credential helper | 3 | 3 | 0 |
| AC4: Skills installed | 6 | 6 | 0 |
| AC5: Hooks in settings.json | 5 | 5 | 0 |
| AC6: Symlinks/PATH | 3 | 3 | 0 |
| AC7: Secrets loaded | 4 | 4 | 0 |
| AC8: Idempotent/recoverable | 4 | 3 | 1 (AC8.4 — setup.sh re-run preserves config) |
| AC9: jq JSON generation | 3 | 3 | 0 |
| AC10: CI contracts | 4 | 4 | 0 |
| AC11: E2E integration | 3 | 3 | 0 |
| AC12: Pre-commit hook | 3 | 2 | 1 (AC12.2 — TTY prompt behavior) |
| **Totals** | **50** | **45** | **5** |

## Test Files by Phase

| Phase | Test Files |
|-------|-----------|
| Phase 1 | `.github/workflows/ci.yml` (feature-guard job), `.github/workflows/publish-features.yml` (verify job) |
| Phase 2 | `tests/test-contracts.sh`, `tests/test-tools.sh` |
| Phase 3 | `tests/test-errors.sh` |
| Phase 4 | `tests/test-bootstrap.sh` |
| Phase 5 | `tests/test-render-devcontainer.sh` |
| Phase 6 | `tests/test-validate-external-refs.sh`, `.github/workflows/ci.yml` (json-validate, external-refs jobs) |
| Phase 7 | `tests/test-pre-commit-hook.sh`, `scripts/test-e2e-bootstrap.sh`, `.github/workflows/ci.yml` (e2e job) |

## Human Verification Criteria

These 5 criteria require manual verification because they depend on interactive terminal behavior or external registry properties that cannot be simulated in CI:

| AC ID | Why Not Automatable | Verification Approach |
|-------|--------------------|-----------------------|
| AC1.4 | OCI registry idempotent overwrite is a registry property, not application logic | Push same tag twice during initial publish, verify manifest digest updates. One-time verification. |
| AC2.2 | Browser-based OAuth flow requires real browser and user interaction | Fresh container, no prior auth. Run bootstrap, verify plain-English explanation appears, `gh auth login --web --git-protocol https` executes, flow blocks until completion. |
| AC2.6 | Interactive prompt with offer/skip choice requires real TTY | Non-psford config with `secrets.provider: "azure"`. Run bootstrap in interactive terminal, verify Azure login prompt appears with skip option. |
| AC8.4 | `setup.sh` interactive config prompt detection requires real terminal session | Run `setup.sh` with existing `.user-config.json`, verify it detects existing config and skips re-prompting. |
| AC12.2 | TTY prompt behavior cannot be verified without a real TTY | Run hook in interactive terminal, verify `read` prompt appears. Piped/non-TTY bypass is tested automatically. |
