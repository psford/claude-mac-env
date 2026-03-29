# Claude Mac Environment Implementation Plan — Phase 4

**Goal:** Create the `tooling-manifest.json` schema and initial populated manifest in `claude-env`, plus the commit-hook classification agent that keeps the manifest current.

**Architecture:** JSON manifest in claude-env repo catalogs all hooks/helpers with tier, language, Feature, and description. A Claude Code pre-commit hook detects new/changed files not in the manifest, invokes an AI classification agent, updates the manifest, and shows the diff for author review.

**Tech Stack:** JSON, Python (for commit hook), Claude Code hooks system

**Scope:** Phase 4 of 8 from original design

**IMPORTANT: This phase operates on the `claude-env` repo (github.com/psford/claude-env), not `claude-mac-env`.** Ensure you have push access to claude-env before starting. Tasks 1 and 2 also create one documentation file in claude-mac-env. Commits are made in both repos.

**Codebase verified:** 2026-03-29 — claude-env repo has 32 guard files in .claude/hooks/, 22+ helpers in helpers/, 8 hook helpers in helpers/hooks/. All four Features defined in claude-mac-env. No tooling-manifest.json exists yet in either repo.

---

## Acceptance Criteria Coverage

### claude-mac-env.AC6: Manifest classification hook
- **claude-mac-env.AC6.1 Success:** New file in claude-env triggers classification agent
- **claude-mac-env.AC6.2 Success:** Agent assigns tier, language, and Feature to new tool
- **claude-mac-env.AC6.3 Success:** Manifest diff shown for author review before push
- **claude-mac-env.AC6.4 Edge:** Already-cataloged file changes don't duplicate manifest entries

---

<!-- START_TASK_1 -->
### Task 1: Define tooling-manifest.json schema

**Files:**
- Create (in claude-env repo): `tooling-manifest.schema.json`
- Create (in claude-mac-env repo): `docs/manifest-schema.md`

**Implementation:**

JSON Schema defining the manifest format:

```json
{
  "$schema": "http://json-schema.org/draft-07/schema#",
  "type": "object",
  "required": ["version", "features", "tools"],
  "properties": {
    "version": { "type": "string", "description": "Schema version" },
    "features": {
      "type": "array",
      "items": {
        "type": "object",
        "required": ["id", "description", "tier"],
        "properties": {
          "id": { "type": "string" },
          "description": { "type": "string" },
          "tier": { "enum": ["always", "universal", "language", "personal"] }
        }
      }
    },
    "tools": {
      "type": "array",
      "items": {
        "type": "object",
        "required": ["name", "source", "tier", "feature", "description"],
        "properties": {
          "name": { "type": "string", "description": "Tool identifier" },
          "source": { "type": "string", "description": "File path relative to claude-env root" },
          "tier": { "enum": ["universal", "language", "personal"] },
          "language": { "type": ["string", "null"], "description": "Language affinity, null if universal" },
          "feature": { "type": "string", "description": "Target Feature ID" },
          "description": { "type": "string", "description": "One-line description for setup.sh display" }
        }
      }
    }
  }
}
```

Also write brief schema documentation in claude-mac-env for reference by setup.sh implementors.

**Verification:**

Validate schema is valid JSON Schema: `python3 -c "import json; json.load(open('tooling-manifest.schema.json'))"`

**Commit (in claude-env):** `feat: add tooling-manifest.json schema definition`
**Commit (in claude-mac-env):** `docs: add manifest schema documentation`
<!-- END_TASK_1 -->

<!-- START_TASK_2 -->
### Task 2: Populate initial tooling-manifest.json

**Files:**
- Create (in claude-env repo): `tooling-manifest.json`

**Implementation:**

Populate the manifest with all existing tools from claude-env, classified based on the investigation results:

**Universal tier (universal-hooks Feature):**
- `.claude/hooks/git_commit_guard.py` — Validates git commit standards
- `.claude/hooks/branch_from_main_guard.py` — Ensures branches originate from main
- `.claude/hooks/cherry_pick_guard.py` — Guards cherry-pick operations
- `.claude/hooks/pre_push_merged_branch_guard.py` — Prevents pushing merged branches
- `.claude/hooks/main_branch_guard.py` — Protects main branch integrity
- `.claude/hooks/shellcheck_write_guard.py` — Validates shell script quality
- `.claude/hooks/spec_staleness_guard.py` — Checks specification freshness
- `.claude/hooks/stale_path_guard.py` — Identifies outdated file paths
- `helpers/hooks/block_main_commits.py` — Git pre-commit: block main commits
- `helpers/hooks/check_log_sanitization.py` — Git pre-commit: CWE-117 prevention
- `helpers/hooks/check_md_table_totals.py` — Git pre-commit: markdown tables
- `helpers/hooks/commit_atomicity_guard.py` — Git pre-commit: atomicity check
- `helpers/hooks/jenkins_pre_push.py` — Git pre-push: CI checks
- `helpers/hooks/validate_doc_links.py` — Git pre-commit: link validation
- `helpers/security_scan.py` — Security analysis tool
- `helpers/zap_scan.py` — OWASP ZAP scanning
- `helpers/check_links.py` — Hyperlink validation
- `helpers/scan_stale_paths.py` — Outdated path identification
- `helpers/load-env.sh` — Environment variable loader

**Language tier (csharp-tools Feature):**
- `.claude/hooks/dotnet_process_guard.py` — .NET process monitoring (language: csharp)
- `.claude/hooks/ef_migration_guard.py` — EF migration enforcement (language: csharp)

**Personal tier (psford-personal Feature):**
- All 22 remaining project-specific guards
- `helpers/test_docs_tabs.py`, `helpers/test_hover_images.py`
- `helpers/generate_stream_deck_icons.py`
- `helpers/Invoke-SpeechToText.ps1`
- Slack integration helpers (5 files)
- `helpers/hooks/check_responsive_tests.py`, `helpers/hooks/validate_hf_urls.py`

The full manifest will be ~60-70 tool entries. Each entry follows the schema from Task 1.

**Verification:**

Validate against schema: `python3 -c "import json; m = json.load(open('tooling-manifest.json')); print(f'{len(m[\"tools\"])} tools cataloged')"`
Verify every file in `.claude/hooks/` and `helpers/` has a manifest entry.

**Commit (in claude-env):** `feat: populate tooling-manifest.json with all existing tools`
<!-- END_TASK_2 -->

<!-- START_TASK_3 -->
### Task 3: Create classification commit hook

**Verifies:** claude-mac-env.AC6.1, claude-mac-env.AC6.2, claude-mac-env.AC6.3, claude-mac-env.AC6.4

**Files:**
- Create (in claude-env repo): `.claude/hooks/manifest_classification_guard.py`

**Implementation:**

A Claude Code hook (registered in settings.json) that runs on file writes/commits. It:

1. On trigger (pre-commit or file write to `.claude/hooks/` or `helpers/`):
   - Read `tooling-manifest.json`
   - Get list of staged/changed files matching hook/helper patterns
   - Filter out files already in the manifest with matching source paths
   - If no uncatalogued files: exit silently (AC6.4)

2. For each uncatalogued file:
   - Read the file content
   - Use Claude Code's AI capabilities to classify:
     - `tier`: universal, language, or personal (based on content analysis — is it language-specific? project-specific? broadly useful?)
     - `language`: null, "csharp", "python", "javascript", etc.
     - `feature`: which Feature this belongs to based on tier/language
     - `description`: one-line summary of what the tool does
   - Add entry to manifest

3. After classification:
   - Write updated `tooling-manifest.json`
   - Show the diff to the author (print added entries)
   - The author reviews the diff as part of the normal commit review
   - Author can manually adjust classifications before pushing

The hook should be a Claude Code hook (not a git hook) so it can use Claude's analysis capabilities for classification. Register it in the Claude Code settings.json hooks configuration.

**Verification:**

In claude-env repo:
1. Create a new file: `helpers/test_new_tool.py` with some content
2. Stage it: `git add helpers/test_new_tool.py`
3. The classification hook should fire and propose a manifest entry
4. Verify the proposed entry has reasonable tier/language/feature
5. Clean up: remove test file, revert manifest changes

**Commit (in claude-env):** `feat: add manifest classification commit hook`
<!-- END_TASK_3 -->
