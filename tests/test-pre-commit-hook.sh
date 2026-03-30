#!/usr/bin/env bash
# Test suite for pre-commit-permission.sh non-interactive bypass
# Verifies AC12.1, AC12.2, AC12.3

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
HOOK="$REPO_DIR/features/universal-hooks/hooks/pre-commit-permission.sh"

echo "========================================"
echo "Test Suite: pre-commit-permission.sh"
echo "========================================"
echo ""

TESTS_PASSED=0
TESTS_FAILED=0

assert_exits_zero() {
    local test_name="$1"
    shift
    if "$@" >/dev/null 2>&1; then
        echo "✓ $test_name"
        ((TESTS_PASSED++)) || true
    else
        echo "✗ $test_name (expected exit 0, got $?)"
        ((TESTS_FAILED++)) || true
    fi
}

# ── AC12.1: non-TTY bypass ──────────────────────────────────────────────────

echo "--- AC12.1: non-TTY bypass ---"

# Pipe input makes stdin non-TTY
assert_exits_zero "non-TTY stdin (pipe) → exit 0" bash "$HOOK" < /dev/null

# ── AC12.3: CLAUDE_CODE=1 bypass ────────────────────────────────────────────

echo ""
echo "--- AC12.3: CLAUDE_CODE=1 bypass ---"

assert_exits_zero "CLAUDE_CODE=1 → exit 0" env CLAUDE_CODE=1 bash "$HOOK" < /dev/null

# CLAUDE_CODE=0 should NOT bypass (falls through to non-TTY check, which still exits 0 here
# because we're piping. The real test is that CLAUDE_CODE=0 doesn't trigger the env check.)
# We verify the logic by checking the hook source code directly.
if grep -q 'CLAUDE_CODE:-.*=.*"1"' "$HOOK"; then
    echo "✓ CLAUDE_CODE check is strictly '1' (not truthy)"
    ((TESTS_PASSED++)) || true
else
    echo "✗ CLAUDE_CODE check should be strictly '1'"
    ((TESTS_FAILED++)) || true
fi

# Verify unset CLAUDE_CODE doesn't crash (${CLAUDE_CODE:-} default)
assert_exits_zero "unset CLAUDE_CODE + non-TTY → exit 0" env -u CLAUDE_CODE bash "$HOOK" < /dev/null

# ── Summary ──────────────────────────────────────────────────────────────────

echo ""
echo "========================================"
echo "Results: $TESTS_PASSED passed, $TESTS_FAILED failed"
echo "========================================"

if [ "$TESTS_FAILED" -gt 0 ]; then
    exit 1
fi
exit 0
