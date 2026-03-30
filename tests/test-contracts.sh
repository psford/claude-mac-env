#!/usr/bin/env bash
# Test suite for config/lib/contracts.sh

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
CONTRACTS_SH="$REPO_DIR/config/lib/contracts.sh"

TEMP_DIR=$(mktemp -d)

# shellcheck disable=SC2317
cleanup() {
    rm -rf "$TEMP_DIR" 2>/dev/null || true
}
trap cleanup EXIT

echo "========================================"
echo "Test Suite: contracts.sh"
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

assert_stderr_contains() {
    local test_name="$1"
    local expected="$2"
    shift 2
    local stderr_output
    stderr_output=$("$@" 2>&1 >/dev/null || true)
    if echo "$stderr_output" | grep -q "$expected"; then
        echo "✓ $test_name"
        ((TESTS_PASSED++)) || true
    else
        echo "✗ $test_name (expected stderr containing '$expected', got: '$stderr_output')"
        ((TESTS_FAILED++)) || true
    fi
}

# Source contracts (in a subshell-safe way for tests)
# shellcheck source=../config/lib/contracts.sh
source "$CONTRACTS_SH"

# ── require_command ──────────────────────────────────────────────────────────

echo "--- require_command ---"
assert_success "require_command bash (exists)" require_command "bash"
assert_success "require_command git (exists)" require_command "git"
assert_failure "require_command nonexistent_tool_xyz (missing)" require_command "nonexistent_tool_xyz"
assert_stderr_contains "require_command error message" "precondition_failed" require_command "nonexistent_tool_xyz"

# ── require_file ─────────────────────────────────────────────────────────────

echo ""
echo "--- require_file ---"
touch "$TEMP_DIR/existing_file.txt"
assert_success "require_file on existing file" require_file "$TEMP_DIR/existing_file.txt"
assert_failure "require_file on missing file" require_file "$TEMP_DIR/no_such_file.txt"
assert_stderr_contains "require_file error message" "precondition_failed" require_file "$TEMP_DIR/no_such_file.txt"

# ── require_dir ──────────────────────────────────────────────────────────────

echo ""
echo "--- require_dir ---"
mkdir -p "$TEMP_DIR/existing_dir"
assert_success "require_dir on existing dir" require_dir "$TEMP_DIR/existing_dir"
assert_failure "require_dir on missing dir" require_dir "$TEMP_DIR/no_such_dir"
assert_stderr_contains "require_dir error message" "precondition_failed" require_dir "$TEMP_DIR/no_such_dir"

# ── require_env ──────────────────────────────────────────────────────────────

echo ""
echo "--- require_env ---"
export TEST_VAR_SET="hello"
assert_success "require_env with set var" require_env "TEST_VAR_SET"
unset TEST_VAR_UNSET 2>/dev/null || true
assert_failure "require_env with unset var" require_env "TEST_VAR_UNSET"
assert_stderr_contains "require_env error message" "precondition_failed" require_env "TEST_VAR_UNSET"

# ── ensure_file_exists ───────────────────────────────────────────────────────

echo ""
echo "--- ensure_file_exists ---"
assert_success "ensure_file_exists on existing file" ensure_file_exists "$TEMP_DIR/existing_file.txt"
assert_failure "ensure_file_exists on missing file" ensure_file_exists "$TEMP_DIR/no_such_file.txt"
assert_stderr_contains "ensure_file_exists error message" "postcondition_failed" ensure_file_exists "$TEMP_DIR/no_such_file.txt"

# ── ensure_valid_json ────────────────────────────────────────────────────────

echo ""
echo "--- ensure_valid_json ---"
echo '{"key": "value"}' > "$TEMP_DIR/valid.json"
echo 'not json at all' > "$TEMP_DIR/invalid.json"
assert_success "ensure_valid_json on valid JSON" ensure_valid_json "$TEMP_DIR/valid.json"
assert_failure "ensure_valid_json on invalid JSON" ensure_valid_json "$TEMP_DIR/invalid.json"
assert_failure "ensure_valid_json on missing file" ensure_valid_json "$TEMP_DIR/no_such_file.json"
assert_stderr_contains "ensure_valid_json error message (invalid)" "postcondition_failed" ensure_valid_json "$TEMP_DIR/invalid.json"

# ── ensure_exit_zero ─────────────────────────────────────────────────────────

echo ""
echo "--- ensure_exit_zero ---"
assert_success "ensure_exit_zero with true" ensure_exit_zero "true command" true
assert_failure "ensure_exit_zero with false" ensure_exit_zero "false command" false
assert_stderr_contains "ensure_exit_zero error message" "postcondition_failed" ensure_exit_zero "false command" false

# ── Summary ──────────────────────────────────────────────────────────────────

echo ""
echo "========================================"
echo "Results: $TESTS_PASSED passed, $TESTS_FAILED failed"
echo "========================================"

if [ "$TESTS_FAILED" -gt 0 ]; then
    exit 1
fi
exit 0
