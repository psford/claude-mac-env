#!/usr/bin/env bash
# Test suite for validate_chain_external_refs()

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
VALIDATE_SH="$REPO_DIR/config/validate-dependencies.sh"

TEMP_DIR=$(mktemp -d)
MOCK_BIN="$TEMP_DIR/mock_bin"
mkdir -p "$MOCK_BIN"

# shellcheck disable=SC2317
cleanup() {
    rm -rf "$TEMP_DIR" 2>/dev/null || true
}
trap cleanup EXIT

echo "========================================"
echo "Test Suite: validate_chain_external_refs"
echo "========================================"
echo ""

TESTS_PASSED=0
TESTS_FAILED=0

assert_equals() {
    local test_name="$1"
    local expected="$2"
    local actual="$3"
    if [ "$expected" = "$actual" ]; then
        echo "✓ $test_name"
        ((TESTS_PASSED++)) || true
    else
        echo "✗ $test_name (expected '$expected', got '$actual')"
        ((TESTS_FAILED++)) || true
    fi
}

assert_output_contains() {
    local test_name="$1"
    local expected="$2"
    local output="$3"
    if echo "$output" | grep -q "$expected"; then
        echo "✓ $test_name"
        ((TESTS_PASSED++)) || true
    else
        echo "✗ $test_name (expected output containing '$expected')"
        ((TESTS_FAILED++)) || true
    fi
}

# ── Valid ref detection (mocked gh succeeds) ─────────────────────────────────

echo "--- Valid ref detection ---"

cat > "$MOCK_BIN/gh" <<'EOF'
#!/bin/bash
case "$1" in
    auth) exit 0 ;;
    repo) echo '{"name":"test"}'; exit 0 ;;
esac
exit 0
EOF
chmod +x "$MOCK_BIN/gh"

# Need timeout in path too
ln -sf "$(command -v timeout)" "$MOCK_BIN/timeout" 2>/dev/null || true

result=$(
    PATH="$MOCK_BIN:$PATH" bash -c '
        source "'"$VALIDATE_SH"'"
        VALIDATION_ERRORS=0
        VALIDATION_WARNINGS=0
        validate_chain_external_refs >/dev/null 2>&1
        echo "$VALIDATION_ERRORS"
    '
)
assert_equals "all refs valid → 0 errors" "0" "$result"

# ── Invalid ref detection (mocked gh fails) ──────────────────────────────────

echo ""
echo "--- Invalid ref detection ---"

cat > "$MOCK_BIN/gh" <<'EOF'
#!/bin/bash
case "$1" in
    auth) exit 0 ;;
    repo) exit 1 ;;  # All repos fail
esac
exit 0
EOF
chmod +x "$MOCK_BIN/gh"

result=$(
    PATH="$MOCK_BIN:$PATH" bash -c '
        source "'"$VALIDATE_SH"'"
        VALIDATION_ERRORS=0
        VALIDATION_WARNINGS=0
        validate_chain_external_refs >/dev/null 2>&1
        echo "$VALIDATION_ERRORS"
    '
)
# Should have 3 errors (3 repos checked)
assert_equals "all refs fail → 3 errors" "3" "$result"

output=$(
    PATH="$MOCK_BIN:$PATH" bash -c '
        source "'"$VALIDATE_SH"'"
        VALIDATION_ERRORS=0
        VALIDATION_WARNINGS=0
        validate_chain_external_refs
    ' 2>&1
)
assert_output_contains "invalid ref output shows NOT FOUND" "NOT FOUND" "$output"

# ── No gh auth → skip gracefully ─────────────────────────────────────────────

echo ""
echo "--- No gh auth → skip gracefully ---"

cat > "$MOCK_BIN/gh" <<'EOF'
#!/bin/bash
case "$1" in
    auth) exit 1 ;;  # Not authenticated
esac
exit 1
EOF
chmod +x "$MOCK_BIN/gh"

result=$(
    PATH="$MOCK_BIN:$PATH" bash -c '
        source "'"$VALIDATE_SH"'"
        VALIDATION_ERRORS=0
        VALIDATION_WARNINGS=0
        validate_chain_external_refs >/dev/null 2>&1
        echo "$VALIDATION_ERRORS"
    '
)
assert_equals "no auth → 0 errors (skipped)" "0" "$result"

output=$(
    PATH="$MOCK_BIN:$PATH" bash -c '
        source "'"$VALIDATE_SH"'"
        VALIDATION_ERRORS=0
        VALIDATION_WARNINGS=0
        validate_chain_external_refs
    ' 2>&1
)
assert_output_contains "no auth → skip message" "skipping" "$output"

# ── Summary ──────────────────────────────────────────────────────────────────

echo ""
echo "========================================"
echo "Results: $TESTS_PASSED passed, $TESTS_FAILED failed"
echo "========================================"

if [ "$TESTS_FAILED" -gt 0 ]; then
    exit 1
fi
exit 0
