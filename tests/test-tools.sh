#!/usr/bin/env bash
# Test suite for config/lib/tools.sh — Layer 1 tool contract tests

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
TOOLS_SH="$REPO_DIR/config/lib/tools.sh"

TEMP_DIR=$(mktemp -d)
MOCK_BIN="$TEMP_DIR/mock_bin"
mkdir -p "$MOCK_BIN"

# shellcheck disable=SC2317
cleanup() {
    rm -rf "$TEMP_DIR" 2>/dev/null || true
}
trap cleanup EXIT

echo "========================================"
echo "Test Suite: tools.sh"
echo "========================================"
echo ""

TESTS_PASSED=0
TESTS_FAILED=0

assert_success() {
    local test_name="$1"
    shift
    if "$@" >/dev/null 2>&1; then
        echo "✓ $test_name"
        ((TESTS_PASSED++)) || true
    else
        echo "✗ $test_name"
        ((TESTS_FAILED++)) || true
    fi
}

assert_failure() {
    local test_name="$1"
    shift
    if ! "$@" >/dev/null 2>&1; then
        echo "✓ $test_name"
        ((TESTS_PASSED++)) || true
    else
        echo "✗ $test_name (expected failure but succeeded)"
        ((TESTS_FAILED++)) || true
    fi
}

assert_stdout_contains() {
    local test_name="$1"
    local expected="$2"
    shift 2
    local stdout_output
    stdout_output=$("$@" 2>/dev/null) || true
    if echo "$stdout_output" | grep -q "$expected"; then
        echo "✓ $test_name"
        ((TESTS_PASSED++)) || true
    else
        echo "✗ $test_name (expected stdout containing '$expected', got: '$stdout_output')"
        ((TESTS_FAILED++)) || true
    fi
}

assert_stderr_contains() {
    local test_name="$1"
    local expected="$2"
    shift 2
    local stderr_output
    stderr_output=$("$@" 2>&1 >/dev/null) || true
    if echo "$stderr_output" | grep -q "$expected"; then
        echo "✓ $test_name"
        ((TESTS_PASSED++)) || true
    else
        echo "✗ $test_name (expected stderr containing '$expected', got: '$stderr_output')"
        ((TESTS_FAILED++)) || true
    fi
}

# Create mock commands
create_mock() {
    local name="$1"
    local exit_code="$2"
    local stdout="${3:-}"
    local stderr="${4:-}"
    cat > "$MOCK_BIN/$name" <<MOCK_EOF
#!/bin/bash
$([ -n "$stderr" ] && echo "echo '$stderr' >&2")
$([ -n "$stdout" ] && echo "echo '$stdout'")
exit $exit_code
MOCK_EOF
    chmod +x "$MOCK_BIN/$name"
}

# Source tools
# shellcheck source=../config/lib/tools.sh
source "$TOOLS_SH"

# ── check_tool ───────────────────────────────────────────────────────────────

echo "--- check_tool ---"
assert_success "check_tool bash (exists)" check_tool "bash"
assert_stdout_contains "check_tool bash has version output" "bash" check_tool "bash"
assert_failure "check_tool nonexistent_xyz (missing)" check_tool "nonexistent_xyz"
assert_stderr_contains "check_tool error type" "missing_tool" check_tool "nonexistent_xyz"

# ── check_gh_auth (mocked) ──────────────────────────────────────────────────

echo ""
echo "--- check_gh_auth ---"

# Mock gh authenticated
create_mock "gh" 0 "Logged in to github.com as testuser"
PATH="$MOCK_BIN:$PATH" assert_stdout_contains "check_gh_auth authed" "authed:" check_gh_auth

# Mock gh not authenticated
create_mock "gh" 1 "" "not logged in"
PATH="$MOCK_BIN:$PATH" assert_stdout_contains "check_gh_auth not authed" "not_authed" check_gh_auth

# ── check_az_auth (mocked) ──────────────────────────────────────────────────

echo ""
echo "--- check_az_auth ---"

# Mock az authenticated
create_mock "az" 0 '{"name": "test-subscription", "id": "abc-123"}'
PATH="$MOCK_BIN:$PATH" assert_stdout_contains "check_az_auth authed" "authed:" check_az_auth

# Mock az not authenticated
create_mock "az" 1 "" "please run az login"
PATH="$MOCK_BIN:$PATH" assert_stdout_contains "check_az_auth not authed" "not_authed" check_az_auth

# ── run_gh_setup_git (mocked) ───────────────────────────────────────────────

echo ""
echo "--- run_gh_setup_git ---"

# Mock gh setup-git succeeding + git config returning gh
create_mock "gh" 0 ""
# We need git config to return "gh" — use real git with a temp config
(
    GIT_CONFIG="$TEMP_DIR/gitconfig"
    export GIT_CONFIG
    git config credential.helper "!/usr/bin/gh auth git-credential"
    create_mock "gh" 0 ""
    PATH="$MOCK_BIN:$PATH" assert_success "run_gh_setup_git success" run_gh_setup_git
)

# Mock gh setup-git failing
create_mock "gh" 1 "" "error"
PATH="$MOCK_BIN:$PATH" assert_failure "run_gh_setup_git failure" run_gh_setup_git
PATH="$MOCK_BIN:$PATH" assert_stderr_contains "run_gh_setup_git error type" "gh_setup_git_failed" run_gh_setup_git

# ── install_skills ───────────────────────────────────────────────────────────

echo ""
echo "--- install_skills ---"

# Set up a fake skills source directory
SKILLS_SOURCE="$TEMP_DIR/skills_source"
SKILLS_TARGET="$TEMP_DIR/skills_target"
mkdir -p "$SKILLS_SOURCE/plugins/test-plugin/skills/brainstorming"
echo "# Brainstorming Skill" > "$SKILLS_SOURCE/plugins/test-plugin/skills/brainstorming/SKILL.md"
mkdir -p "$SKILLS_SOURCE/plugins/test-plugin/skills/coding"
echo "# Coding Skill" > "$SKILLS_SOURCE/plugins/test-plugin/skills/coding/SKILL.md"
mkdir -p "$SKILLS_TARGET"

assert_success "install_skills with valid source" install_skills "$SKILLS_SOURCE" "$SKILLS_TARGET"
assert_stdout_contains "install_skills count" "2" install_skills "$SKILLS_SOURCE" "$SKILLS_TARGET"

# Verify brainstorming skill exists in target (AC4.3)
if [ -f "$SKILLS_TARGET/brainstorming/SKILL.md" ]; then
    echo "✓ install_skills brainstorming skill exists in target (AC4.3)"
    ((TESTS_PASSED++)) || true
else
    echo "✗ install_skills brainstorming skill exists in target (AC4.3)"
    ((TESTS_FAILED++)) || true
fi

# Empty source (no skills)
EMPTY_SOURCE="$TEMP_DIR/empty_source"
mkdir -p "$EMPTY_SOURCE"
EMPTY_TARGET="$TEMP_DIR/empty_target"
mkdir -p "$EMPTY_TARGET"
assert_failure "install_skills with no skills" install_skills "$EMPTY_SOURCE" "$EMPTY_TARGET"
assert_stderr_contains "install_skills error type" "no_skills_found" install_skills "$EMPTY_SOURCE" "$EMPTY_TARGET"

# ── merge_settings_json ──────────────────────────────────────────────────────

echo ""
echo "--- merge_settings_json ---"

# Merge into non-existent target (AC5.1)
NEW_TARGET="$TEMP_DIR/new_settings.json"
assert_success "merge_settings_json into new file" merge_settings_json '{"hooks": {"PreToolUse": [{"matcher": "Bash"}]}}' "$NEW_TARGET"

# Verify the file is valid JSON
if jq . "$NEW_TARGET" >/dev/null 2>&1; then
    echo "✓ merge_settings_json new file is valid JSON"
    ((TESTS_PASSED++)) || true
else
    echo "✗ merge_settings_json new file is valid JSON"
    ((TESTS_FAILED++)) || true
fi

# Merge into existing target — preserves existing keys (AC5.2)
EXISTING_TARGET="$TEMP_DIR/existing_settings.json"
echo '{"permissions": {"allow": ["Bash(*)"]}, "existing_key": true}' | jq . > "$EXISTING_TARGET"
assert_success "merge_settings_json into existing file" merge_settings_json '{"hooks": {"PreToolUse": []}}' "$EXISTING_TARGET"

# Verify existing keys preserved
if jq -e '.existing_key' "$EXISTING_TARGET" >/dev/null 2>&1; then
    echo "✓ merge_settings_json preserves existing keys (AC5.2)"
    ((TESTS_PASSED++)) || true
else
    echo "✗ merge_settings_json preserves existing keys (AC5.2)"
    ((TESTS_FAILED++)) || true
fi

# Verify new keys added
if jq -e '.hooks.PreToolUse' "$EXISTING_TARGET" >/dev/null 2>&1; then
    echo "✓ merge_settings_json adds new keys"
    ((TESTS_PASSED++)) || true
else
    echo "✗ merge_settings_json adds new keys"
    ((TESTS_FAILED++)) || true
fi

# Invalid JSON fragment
assert_failure "merge_settings_json with invalid JSON" merge_settings_json 'not json' "$TEMP_DIR/bad.json"
assert_stderr_contains "merge_settings_json error type" "json_merge_failed" merge_settings_json 'not json' "$TEMP_DIR/bad.json"

# ── fix_symlink ──────────────────────────────────────────────────────────────

echo ""
echo "--- fix_symlink ---"

# Create a mock executable
MOCK_EXEC="$TEMP_DIR/mock_exec"
cat > "$MOCK_EXEC" <<'EXEC_EOF'
#!/bin/bash
echo "mock 1.0.0"
EXEC_EOF
chmod +x "$MOCK_EXEC"

SYMLINK_TARGET="$TEMP_DIR/mock_exec_link"
assert_success "fix_symlink creates new symlink (AC6.1)" fix_symlink "$MOCK_EXEC" "$SYMLINK_TARGET"

# Verify symlink exists
if [ -L "$SYMLINK_TARGET" ]; then
    echo "✓ fix_symlink target is a symlink"
    ((TESTS_PASSED++)) || true
else
    echo "✗ fix_symlink target is a symlink"
    ((TESTS_FAILED++)) || true
fi

# Already correct — no-op (AC6.2)
assert_success "fix_symlink already correct is no-op (AC6.2)" fix_symlink "$MOCK_EXEC" "$SYMLINK_TARGET"

# ── Summary ──────────────────────────────────────────────────────────────────

echo ""
echo "========================================"
echo "Results: $TESTS_PASSED passed, $TESTS_FAILED failed"
echo "========================================"

if [ "$TESTS_FAILED" -gt 0 ]; then
    exit 1
fi
exit 0
