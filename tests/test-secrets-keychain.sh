#!/usr/bin/env bash
# Test suite for secrets-keychain.sh provider

set -uo pipefail

PROVIDER_SCRIPT="/private/tmp/claude-mac-env/config/secrets-keychain.sh"
INTERFACE_SCRIPT="/private/tmp/claude-mac-env/config/secrets-interface.sh"
TEMP_DIR=$(mktemp -d)
TEST_OUTPUT_FILE="$TEMP_DIR/secrets.env"
TEST_CONFIG_FILE="$TEMP_DIR/config.json"
MOCK_SECURITY_SCRIPT="$TEMP_DIR/mock_security.sh"

cleanup() {
    rm -rf "$TEMP_DIR" 2>/dev/null || true
}
trap cleanup EXIT

echo "========================================"
echo "Test Suite: secrets-keychain.sh Provider"
echo "========================================"
echo ""

TESTS_PASSED=0
TESTS_FAILED=0

assert_success() {
    local test_name="$1"
    shift

    if "$@" >/dev/null 2>&1; then
        echo "✓ $test_name"
        ((TESTS_PASSED++))
    else
        echo "✗ $test_name"
        "$@" 2>&1 | head -5
        ((TESTS_FAILED++))
    fi
}

assert_failure() {
    local test_name="$1"
    shift

    if ! "$@" >/dev/null 2>&1; then
        echo "✓ $test_name"
        ((TESTS_PASSED++))
    else
        echo "✗ $test_name (expected failure but succeeded)"
        ((TESTS_FAILED++))
    fi
}

assert_output_contains() {
    local test_name="$1"
    local search_text="$2"
    shift 2

    local output
    output=$("$@" 2>&1)

    if echo "$output" | grep -q "$search_text"; then
        echo "✓ $test_name"
        ((TESTS_PASSED++))
    else
        echo "✗ $test_name (output did not contain '$search_text')"
        echo "  Got: $output"
        ((TESTS_FAILED++))
    fi
}

# Test 1: secrets_describe() returns expected text
assert_output_contains "describe returns correct text" "Read secrets from macOS Keychain" \
    bash -c "source '$INTERFACE_SCRIPT' && source '$PROVIDER_SCRIPT' && secrets_describe"

# Test 2: secrets_validate() succeeds when security command exists and accounts configured
mkdir -p "$TEMP_DIR/mock_bin"
export PATH="$TEMP_DIR/mock_bin:$PATH"

cat > "$TEST_CONFIG_FILE" <<EOF
{
  "secrets": {
    "provider": "keychain",
    "keychainService": "claude-env",
    "keychainAccounts": ["API_KEY", "DB_URL"]
  }
}
EOF

# Create a mock security command
cat > "$TEMP_DIR/mock_bin/security" <<'EOF'
#!/bin/bash
exit 0
EOF
chmod +x "$TEMP_DIR/mock_bin/security"

assert_success "validate succeeds when security command exists, service and accounts configured" \
    bash -c "export USER_CONFIG='$TEST_CONFIG_FILE' && source '$INTERFACE_SCRIPT' && source '$PROVIDER_SCRIPT' && secrets_validate"

# Test 3: secrets_validate() fails when service not configured
cat > "$TEST_CONFIG_FILE" <<EOF
{
  "secrets": {
    "provider": "keychain",
    "keychainAccounts": ["API_KEY"]
  }
}
EOF

assert_failure "validate fails when keychain service not configured" \
    bash -c "export USER_CONFIG='$TEST_CONFIG_FILE' && source '$INTERFACE_SCRIPT' && source '$PROVIDER_SCRIPT' && secrets_validate"

# Test 4: secrets_validate() fails when accounts not configured
cat > "$TEST_CONFIG_FILE" <<EOF
{
  "secrets": {
    "provider": "keychain",
    "keychainService": "claude-env"
  }
}
EOF

assert_failure "validate fails when keychain accounts not configured" \
    bash -c "export USER_CONFIG='$TEST_CONFIG_FILE' && source '$INTERFACE_SCRIPT' && source '$PROVIDER_SCRIPT' && secrets_validate"

# Test 5: secrets_inject() writes export format from keychain using account list
cat > "$TEST_CONFIG_FILE" <<EOF
{
  "secrets": {
    "provider": "keychain",
    "keychainService": "claude-env",
    "keychainAccounts": ["API_KEY", "DB_URL"]
  }
}
EOF

# Create mock security that simulates keychain with secrets
cat > "$TEMP_DIR/mock_bin/security" <<'EOF'
#!/bin/bash
if [[ "$1" == "find-generic-password" ]]; then
    # Fetch secret by service and account
    if [[ "$@" == *"-s"*"claude-env"* && "$@" == *"-a"*"API_KEY"* && "$@" == *"-w"* ]]; then
        echo "secret123"
        exit 0
    elif [[ "$@" == *"-s"*"claude-env"* && "$@" == *"-a"*"DB_URL"* && "$@" == *"-w"* ]]; then
        echo "postgres://localhost/test"
        exit 0
    fi
    exit 1
fi

exit 1
EOF
chmod +x "$TEMP_DIR/mock_bin/security"

assert_success "inject creates output file with secrets from keychain account list" \
    bash -c "export USER_CONFIG='$TEST_CONFIG_FILE' && export SECRETS_OUTPUT_PATH='$TEST_OUTPUT_FILE' && source '$INTERFACE_SCRIPT' && source '$PROVIDER_SCRIPT' && secrets_inject && test -f '$TEST_OUTPUT_FILE'"

# Test 6: secrets_inject() reads secrets from keychain correctly and quotes values
assert_output_contains "output contains API_KEY with quotes" 'API_KEY="secret123"' \
    cat "$TEST_OUTPUT_FILE"

assert_output_contains "output contains DB_URL with quotes" 'DB_URL="postgres' \
    cat "$TEST_OUTPUT_FILE"

# Test 7: secrets_inject() handles empty accounts gracefully
cat > "$TEST_CONFIG_FILE" <<EOF
{
  "secrets": {
    "provider": "keychain",
    "keychainService": "claude-env",
    "keychainAccounts": []
  }
}
EOF

assert_success "inject handles empty accounts list gracefully" \
    bash -c "export USER_CONFIG='$TEST_CONFIG_FILE' && export SECRETS_OUTPUT_PATH='$TEST_OUTPUT_FILE' && source '$INTERFACE_SCRIPT' && source '$PROVIDER_SCRIPT' && secrets_inject && test -f '$TEST_OUTPUT_FILE'"

# Summary
echo ""
echo "========================================"
echo "Results: $TESTS_PASSED passed, $TESTS_FAILED failed"
echo "========================================"

if [[ $TESTS_FAILED -eq 0 ]]; then
    echo "✓ All tests passed!"
    exit 0
else
    echo "✗ Some tests failed"
    exit 1
fi
