#!/usr/bin/env bash
# Test suite for secrets-azure.sh provider

set -uo pipefail

PROVIDER_SCRIPT="/private/tmp/claude-mac-env/config/secrets-azure.sh"
INTERFACE_SCRIPT="/private/tmp/claude-mac-env/config/secrets-interface.sh"
TEMP_DIR=$(mktemp -d)
TEST_OUTPUT_FILE="$TEMP_DIR/secrets.env"
TEST_CONFIG_FILE="$TEMP_DIR/config.json"
MOCK_AZ_SCRIPT="$TEMP_DIR/mock_az.sh"  # used in test cases below
export MOCK_AZ_SCRIPT

# shellcheck disable=SC2317
cleanup() {
    rm -rf "$TEMP_DIR" 2>/dev/null || true
}
trap cleanup EXIT

echo "========================================"
echo "Test Suite: secrets-azure.sh Provider"
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
assert_output_contains "describe returns correct text" "Pull secrets from Azure Key Vault" \
    bash -c "source '$INTERFACE_SCRIPT' && source '$PROVIDER_SCRIPT' && secrets_describe"

# Test 2: secrets_validate() fails when az CLI is not installed
mkdir -p "$TEMP_DIR/mock_bin"
export PATH="$TEMP_DIR/mock_bin:$PATH"

cat > "$TEST_CONFIG_FILE" <<EOF
{
  "secrets": {
    "provider": "azure",
    "azureVaultName": "my-vault"
  }
}
EOF

assert_failure "validate fails when az CLI not installed" \
    bash -c "export USER_CONFIG='$TEST_CONFIG_FILE' && source '$INTERFACE_SCRIPT' && source '$PROVIDER_SCRIPT' && secrets_validate"

# Test 3: secrets_validate() fails when vault name not configured
# Create a mock az CLI
cat > "$TEMP_DIR/mock_bin/az" <<'EOF'
#!/bin/bash
if [[ "$1" == "account" && "$2" == "show" ]]; then
    echo '{"id":"test-subscription"}'
    exit 0
fi
exit 1
EOF
chmod +x "$TEMP_DIR/mock_bin/az"

cat > "$TEST_CONFIG_FILE" <<EOF
{
  "secrets": {
    "provider": "azure"
  }
}
EOF

assert_failure "validate fails when vault name not configured" \
    bash -c "export USER_CONFIG='$TEST_CONFIG_FILE' && source '$INTERFACE_SCRIPT' && source '$PROVIDER_SCRIPT' && secrets_validate"

# Test 4: secrets_validate() fails when az account show fails
cat > "$TEST_CONFIG_FILE" <<EOF
{
  "secrets": {
    "provider": "azure",
    "azureVaultName": "my-vault"
  }
}
EOF

# Create a mock az that fails for account show
cat > "$TEMP_DIR/mock_bin/az" <<'EOF'
#!/bin/bash
if [[ "$1" == "account" && "$2" == "show" ]]; then
    echo "error: not authenticated" >&2
    exit 1
fi
exit 0
EOF
chmod +x "$TEMP_DIR/mock_bin/az"

assert_failure "validate fails when az not authenticated" \
    bash -c "export USER_CONFIG='$TEST_CONFIG_FILE' && source '$INTERFACE_SCRIPT' && source '$PROVIDER_SCRIPT' && secrets_validate"

# Test 5: secrets_validate() succeeds when az is installed and authenticated
cat > "$TEMP_DIR/mock_bin/az" <<'EOF'
#!/bin/bash
if [[ "$1" == "account" && "$2" == "show" ]]; then
    echo '{"id":"test-subscription"}'
    exit 0
fi
exit 0
EOF
chmod +x "$TEMP_DIR/mock_bin/az"

assert_success "validate succeeds when az authenticated and vault configured" \
    bash -c "export USER_CONFIG='$TEST_CONFIG_FILE' && source '$INTERFACE_SCRIPT' && source '$PROVIDER_SCRIPT' && secrets_validate"

# Test 6: secrets_inject() calls az keyvault secret list and writes exports
cat > "$TEMP_DIR/mock_bin/az" <<'EOF'
#!/bin/bash
if [[ "$1" == "keyvault" && "$2" == "secret" && "$3" == "list" ]]; then
    echo "api-key"
    echo "db-url"
    exit 0
fi

if [[ "$1" == "keyvault" && "$2" == "secret" && "$3" == "show" ]]; then
    if [[ "$4" == "--vault-name" && "$5" == "my-vault" && "$6" == "--name" ]]; then
        if [[ "$7" == "api-key" ]]; then
            echo "secret123"
        elif [[ "$7" == "db-url" ]]; then
            echo "postgres://localhost/test"
        fi
    fi
    exit 0
fi
exit 1
EOF
chmod +x "$TEMP_DIR/mock_bin/az"

assert_success "inject creates output file with secrets" \
    bash -c "export USER_CONFIG='$TEST_CONFIG_FILE' && export SECRETS_OUTPUT_PATH='$TEST_OUTPUT_FILE' && source '$INTERFACE_SCRIPT' && source '$PROVIDER_SCRIPT' && secrets_inject && test -f '$TEST_OUTPUT_FILE'"

# Test 7: secrets_inject() converts kebab-case to UPPER_SNAKE_CASE and quotes values
assert_output_contains "output contains API_KEY with quotes" 'API_KEY="secret123"' \
    cat "$TEST_OUTPUT_FILE"

assert_output_contains "output contains DB_URL with quotes" 'DB_URL="postgres' \
    cat "$TEST_OUTPUT_FILE"

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
