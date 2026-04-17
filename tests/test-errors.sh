#!/usr/bin/env bash
# Test suite for config/lib/errors.sh — Layer 2 error handler tests

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
ERRORS_SH="$REPO_DIR/config/lib/errors.sh"

echo "========================================"
echo "Test Suite: errors.sh"
echo "========================================"
echo ""

TESTS_PASSED=0
TESTS_FAILED=0

assert_starts_with() {
    local test_name="$1"
    local expected_prefix="$2"
    local actual="$3"
    if [[ "$actual" == "${expected_prefix}"* ]]; then
        echo "✓ $test_name"
        ((TESTS_PASSED++)) || true
    else
        echo "✗ $test_name (expected prefix '$expected_prefix', got: '$actual')"
        ((TESTS_FAILED++)) || true
    fi
}

assert_contains() {
    local test_name="$1"
    local expected="$2"
    local actual="$3"
    if echo "$actual" | grep -q "$expected"; then
        echo "✓ $test_name"
        ((TESTS_PASSED++)) || true
    else
        echo "✗ $test_name (expected to contain '$expected', got: '$actual')"
        ((TESTS_FAILED++)) || true
    fi
}

# ── Action mapping ───────────────────────────────────────────────────────────
# Each test sources errors.sh in a subshell to get fresh retry counts.

echo "--- Action mapping ---"

result=$(bash -c "source '$ERRORS_SH'; handle_error missing_tool 'jq' ''")
assert_starts_with "missing_tool → abort" "abort:" "$result"

result=$(bash -c "source '$ERRORS_SH'; handle_error gh_login_failed '' ''")
assert_starts_with "gh_login_failed (first) → retry" "retry:" "$result"

result=$(bash -c "source '$ERRORS_SH'; handle_error clone_failed '' ''")
assert_starts_with "clone_failed (first) → retry" "retry:" "$result"

result=$(bash -c "source '$ERRORS_SH'; handle_error no_skills_found '' ''")
assert_starts_with "no_skills_found → abort" "abort:" "$result"

result=$(bash -c "source '$ERRORS_SH'; handle_error json_merge_failed '' ''")
assert_starts_with "json_merge_failed → abort" "abort:" "$result"

result=$(bash -c "source '$ERRORS_SH'; handle_error symlink_failed '' ''")
assert_starts_with "symlink_failed → skip" "skip:" "$result"

result=$(bash -c "source '$ERRORS_SH'; handle_error secrets_failed '' ''")
assert_starts_with "secrets_failed → skip" "skip:" "$result"

# ── Retry exhaustion (AC2.8) ────────────────────────────────────────────────

echo ""
echo "--- Retry exhaustion (AC2.8) ---"

# gh_login_failed: max 3 retries, 4th should abort
results=$(bash -c "
    source '$ERRORS_SH'
    handle_error gh_login_failed '' ''
    handle_error gh_login_failed '' ''
    handle_error gh_login_failed '' ''
    handle_error gh_login_failed '' ''
")

call1=$(echo "$results" | sed -n '1p')
call2=$(echo "$results" | sed -n '2p')
call3=$(echo "$results" | sed -n '3p')
call4=$(echo "$results" | sed -n '4p')

assert_starts_with "gh_login_failed call 1 → retry" "retry:" "$call1"
assert_starts_with "gh_login_failed call 2 → retry" "retry:" "$call2"
assert_starts_with "gh_login_failed call 3 → retry" "retry:" "$call3"
assert_starts_with "gh_login_failed call 4 → abort" "abort:" "$call4"
assert_contains "gh_login_failed exhausted message contains 'No worries'" "No worries" "$call4"

# clone_failed: max 2 retries, 3rd should abort
results=$(bash -c "
    source '$ERRORS_SH'
    handle_error clone_failed '' ''
    handle_error clone_failed '' ''
    handle_error clone_failed '' ''
")

call1=$(echo "$results" | sed -n '1p')
call2=$(echo "$results" | sed -n '2p')
call3=$(echo "$results" | sed -n '3p')

assert_starts_with "clone_failed call 1 → retry" "retry:" "$call1"
assert_starts_with "clone_failed call 2 → retry" "retry:" "$call2"
assert_starts_with "clone_failed call 3 → abort" "abort:" "$call3"

# gh_setup_git_failed: max 1 retry, 2nd should skip
results=$(bash -c "
    source '$ERRORS_SH'
    handle_error gh_setup_git_failed '' ''
    handle_error gh_setup_git_failed '' ''
")

call1=$(echo "$results" | sed -n '1p')
call2=$(echo "$results" | sed -n '2p')

assert_starts_with "gh_setup_git_failed call 1 → retry" "retry:" "$call1"
assert_starts_with "gh_setup_git_failed call 2 → skip" "skip:" "$call2"

# ── Message quality (brother-in-law test) ────────────────────────────────────

echo ""
echo "--- Message quality ---"

result=$(bash -c "source '$ERRORS_SH'; handle_error clone_failed '' ''")
assert_contains "clone_failed message: 'Couldn't reach GitHub'" "Couldn't reach GitHub" "$result"

result=$(bash -c "source '$ERRORS_SH'; handle_error secrets_failed '' ''")
assert_contains "secrets_failed message: 'Secrets couldn't load'" "Secrets couldn't load" "$result"

result=$(bash -c "source '$ERRORS_SH'; handle_error json_merge_failed '' ''")
assert_contains "json_merge_failed message: 'corrupt'" "corrupt" "$result"

result=$(bash -c "source '$ERRORS_SH'; handle_error missing_tool 'jq' ''")
assert_contains "missing_tool message: 'Dockerfile'" "Dockerfile" "$result"

# ── Unknown error type ───────────────────────────────────────────────────────

echo ""
echo "--- Unknown error type ---"

result=$(bash -c "source '$ERRORS_SH'; handle_error unknown_xyz 'something broke' ''")
assert_starts_with "unknown error → abort" "abort:" "$result"
assert_contains "unknown error message: 'Unknown error'" "Unknown error" "$result"

# ── Summary ──────────────────────────────────────────────────────────────────

echo ""
echo "========================================"
echo "Results: $TESTS_PASSED passed, $TESTS_FAILED failed"
echo "========================================"

if [ "$TESTS_FAILED" -gt 0 ]; then
    exit 1
fi
exit 0
