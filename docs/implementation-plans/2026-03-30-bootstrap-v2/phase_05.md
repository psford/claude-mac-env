# Bootstrap v2 Implementation Plan — Phase 5

**Goal:** Replace bash string substitution for JSON generation in `setup.sh` with `jq`, eliminating an entire class of silent malformed-JSON bugs.

**Architecture:** The current `render_devcontainer()` function (setup.sh:810-915) uses bash `${var//pattern/replacement}` to fill template placeholders. This is fragile — special characters in mount paths, unescaped quotes, or missing commas produce invalid JSON silently. The new approach: convert the template to a valid JSON base file, use `jq` to build the output programmatically, and validate with `jq .` after every render.

**Tech Stack:** Bash, jq

**Scope:** Phase 5 of 7 from original design

**Codebase verified:** 2026-03-30

---

## Acceptance Criteria Coverage

This phase implements and tests:

### bootstrap-v2.AC9: JSON generation uses jq
- **bootstrap-v2.AC9.1 Success:** `render_devcontainer()` uses only `jq` for JSON manipulation
- **bootstrap-v2.AC9.2 Success:** `jq . < .devcontainer/devcontainer.json` exits 0 after every render
- **bootstrap-v2.AC9.3 Failure:** No `sed`, `awk`, or bash variable substitution operates on JSON content in setup.sh

---

<!-- START_TASK_1 -->
### Task 1: Convert devcontainer.json.template to a valid JSON base file

**Files:**
- Modify: `.devcontainer/devcontainer.json.template` (rewrite entirely)

**Step 1: Rewrite the template as valid JSON**

Replace the entire contents of `.devcontainer/devcontainer.json.template` with a valid JSON file that `jq` can parse. Placeholder tokens like `{{BASE_IMAGE}}` are removed — `jq` will inject values programmatically.

```json
{
  "name": "Claude Dev Environment",
  "build": {
    "dockerfile": "../Dockerfile",
    "context": "..",
    "args": {
      "BASE_IMAGE": "ubuntu:24.04"
    }
  },
  "remoteUser": "claude",
  "features": {},
  "mounts": [
    "source=${localEnv:HOME}/.gitconfig,target=/home/claude/.gitconfig,type=bind,readonly",
    "source=${localEnv:HOME}/.ssh,target=/home/claude/.ssh,type=bind,readonly"
  ],
  "workspaceFolder": "/workspaces",
  "customizations": {
    "vscode": {
      "extensions": [
        "anthropics.claude-code"
      ]
    }
  },
  "postCreateCommand": "bash /workspaces/.claude-mac-env/config/bootstrap.sh"
}
```

The default values (ubuntu:24.04, empty features, base mounts) serve as the starting point. `jq` will override them based on `.user-config.json`.

**Step 2: Verify the template is valid JSON**

Run:
```bash
jq . .devcontainer/devcontainer.json.template > /dev/null
```
Expected: Exit 0 (valid JSON)

**Step 3: Commit**

```bash
git add .devcontainer/devcontainer.json.template
git commit -m "refactor: convert devcontainer.json.template to valid JSON base

Removes {{placeholder}} tokens. jq will inject values programmatically
instead of bash string substitution."
```

<!-- END_TASK_1 -->

<!-- START_TASK_2 -->
### Task 2: Rewrite render_devcontainer() to use jq

**Files:**
- Modify: `setup.sh` (lines 810-915 — replace `render_devcontainer()` function)

**Implementation:**

Rewrite `render_devcontainer()` to build the output JSON entirely with `jq`. The function should:

1. Read the base template with `jq` (not `cat`)
2. Read config values from `.user-config.json` with `jq`
3. Build features object: map feature names to GHCR URLs using `jq`
4. Build mounts array: start with project mounts from `projectDirs`, add config/ mount, add .user-config.json mount, conditionally add .env mount, then prepend to existing template mounts — all using `jq`
5. Set base image using `jq --arg`
6. Conditionally add csharp extension using `jq`
7. Update postCreateCommand using `jq`
8. Write output
9. Postcondition: `jq . < output_file > /dev/null` (validate result is valid JSON)

Key constraints:
- Zero bash string concatenation for JSON content
- All JSON manipulation via `jq` pipes or `jq --arg`/`--argjson`
- Template is read and modified as a JSON object, not as text
- Mount strings are built using `jq` string interpolation, not bash variable expansion in quoted strings
- The `${localEnv:HOME}` syntax in mount paths is a Dev Containers variable, NOT a bash variable — it must be preserved literally in the output JSON

The function should still use the same UX helpers (`info`, `success`, `error`) for progress messages since those are Layer 3 concerns in setup.sh.

**Verification:**
Run: `shellcheck setup.sh`
Expected: No new errors introduced

Run (after rendering):
```bash
jq . .devcontainer/devcontainer.json > /dev/null
```
Expected: Exit 0 — generated file is valid JSON

**Commit:** `refactor: rewrite render_devcontainer() to use jq for all JSON manipulation`

<!-- END_TASK_2 -->

<!-- START_TASK_3 -->
### Task 3: Add render_devcontainer_json() to config/lib/tools.sh as Layer 1 function

**Files:**
- Modify: `config/lib/tools.sh` (append new function)

**Implementation:**

Add a Layer 1 tool function `render_devcontainer_json(config_path, template_path, output_path)` to `config/lib/tools.sh`. This is the design-by-contract version that `setup.sh`'s `render_devcontainer()` delegates the JSON work to.

Preconditions:
- `require_file "$config_path"` (.user-config.json)
- `require_file "$template_path"` (devcontainer.json.template)
- `require_command jq`

Work:
- Read template as JSON via `jq`
- Extract config values via `jq`
- Build and merge all JSON content via `jq`
- Write output

Postconditions:
- `ensure_file_exists "$output_path"`
- `ensure_valid_json "$output_path"`

Returns: exit 0 on success, exit 1 with `json_render_failed` on stderr if postcondition fails.

**Verification:**
Run: `shellcheck config/lib/tools.sh`
Expected: No errors

**Commit:** `feat: add render_devcontainer_json() Layer 1 tool function`

<!-- END_TASK_3 -->

<!-- START_TASK_4 -->
### Task 4: Test render_devcontainer_json and verify no bash JSON substitution remains

**Verifies:** bootstrap-v2.AC9.1, bootstrap-v2.AC9.2, bootstrap-v2.AC9.3

**Files:**
- Create: `tests/test-render-devcontainer.sh`

**Testing:**
Follow the project's existing test pattern.

Tests must verify:

**bootstrap-v2.AC9.1 — jq only:**
- Create a test `.user-config.json` and template in TEMP_DIR
- Call `render_devcontainer_json`
- Output file exists and is valid JSON (`jq .` exits 0)
- Features contain GHCR URLs (`jq '.features | keys[]'` output contains `ghcr.io/psford/claude-mac-env/`)
- Base image is set correctly (`jq -r '.build.args.BASE_IMAGE'`)
- Project mounts are present in `.mounts` array
- `${localEnv:HOME}` mounts preserved literally

**bootstrap-v2.AC9.2 — output is valid JSON:**
- Render with various configs (empty features, multiple project dirs, env secrets provider)
- Every output passes `jq .` validation

**bootstrap-v2.AC9.3 — no bash JSON substitution in setup.sh:**
- `grep -c '{{' setup.sh` returns 0 (no template placeholders left in render function)
- `grep -c 'rendered=.*{rendered//' setup.sh` returns 0 (no bash parameter expansion on JSON)

**Verification:**
Run: `bash tests/test-render-devcontainer.sh`
Expected: All tests pass

**Commit:** `test: add render_devcontainer_json contract tests`

<!-- END_TASK_4 -->

<!-- START_TASK_5 -->
### Task 5: Verify full test suite passes

**Files:** None (verification only)

**Step 1: Run all tests**

Run:
```bash
bash tests/test-contracts.sh && bash tests/test-tools.sh && bash tests/test-errors.sh && bash tests/test-bootstrap.sh && bash tests/test-render-devcontainer.sh
```
Expected: All tests pass

**Step 2: Run shellcheck on all modified files**

Run:
```bash
shellcheck setup.sh config/lib/tools.sh
```
Expected: No errors
<!-- END_TASK_5 -->
