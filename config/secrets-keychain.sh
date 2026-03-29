#!/usr/bin/env bash
# Secrets provider: macOS Keychain reader
#
# Reads secrets from macOS Keychain using the security CLI.
# This provider runs on the Mac HOST (before container start), not inside container.
# macOS Keychain is not accessible from inside Docker.
#
# Two-phase approach:
# 1. Host-side (during setup.sh): Read from Keychain, write to ~/.claude-secrets.env
# 2. Container-side (during postCreateCommand): The file is bind-mounted, source it
#
# Configuration (in .user-config.json):
#   secrets.keychainService: Service name in Keychain (all secrets stored under this service)
#   secrets.keychainAccounts: Array of account names to fetch from Keychain
#
# Usage: Add secrets to Keychain with:
#   security add-generic-password -s "claude-env" -a "API_KEY" -w "value"

set -euo pipefail

# Check for jq availability
if ! command -v jq &>/dev/null; then
  echo "error: jq is required but not installed" >&2
  return 1 2>/dev/null || exit 1
fi

# Describe this provider for the setup menu
secrets_describe() {
    echo "Read secrets from macOS Keychain"
}

# Validate that security command exists, service is configured, and accounts are listed
# Returns 0 if valid, 1 if not (with error message to stderr)
secrets_validate() {
    # Check if security command exists (always present on macOS)
    if ! command -v security &>/dev/null; then
        echo "error: security command not found. This provider requires macOS." >&2
        return 1
    fi

    # Read config file to get service name
    if [[ ! -f "${USER_CONFIG:-.user-config.json}" ]]; then
        echo "error: user config file not found: ${USER_CONFIG:-.user-config.json}" >&2
        return 1
    fi

    # Extract keychain service name from config using jq
    local service_name
    service_name=$(jq -r '.secrets.keychainService // empty' "${USER_CONFIG:-.user-config.json}" 2>/dev/null)

    if [[ -z "$service_name" ]]; then
        echo "error: secrets.keychainService not configured in user config" >&2
        return 1
    fi

    # Check that accounts array is configured and not empty
    local accounts
    accounts=$(jq -r '.secrets.keychainAccounts[]? // empty' "${USER_CONFIG:-.user-config.json}" 2>/dev/null)

    if [[ -z "$accounts" ]]; then
        echo "error: secrets.keychainAccounts not configured in user config" >&2
        return 1
    fi

    return 0
}

# Inject secrets from macOS Keychain into $SECRETS_OUTPUT_PATH
# Fetches secrets from keychain using account names listed in config
# Service name acts as namespace - secrets stored under one service with different account names
secrets_inject() {
    # Read config file to get service name and accounts
    if [[ ! -f "${USER_CONFIG:-.user-config.json}" ]]; then
        echo "error: user config file not found: ${USER_CONFIG:-.user-config.json}" >&2
        return 1
    fi

    local service_name
    service_name=$(jq -r '.secrets.keychainService // empty' "${USER_CONFIG:-.user-config.json}" 2>/dev/null)

    if [[ -z "$service_name" ]]; then
        echo "error: secrets.keychainService not configured in user config" >&2
        return 1
    fi

    # Ensure output path is set
    local output_path="${SECRETS_OUTPUT_PATH:-/home/claude/.secrets.env}"

    # Create temporary file to avoid partial writes
    local temp_output
    temp_output=$(mktemp)
    # shellcheck disable=SC2064
    trap "rm -f '$temp_output'" RETURN

    # Get list of accounts from config array
    local accounts
    accounts=$(jq -r '.secrets.keychainAccounts[]? // empty' "${USER_CONFIG:-.user-config.json}" 2>/dev/null)

    if [[ -z "$accounts" ]]; then
        # No accounts configured - create empty file
        mkdir -p "$(dirname "$output_path")"
        touch "$temp_output"
        mv "$temp_output" "$output_path"
        chmod 600 "$output_path"
        return 0
    fi

    # For each account, fetch the password and write as export
    while IFS= read -r account_name; do
        [[ -z "$account_name" ]] && continue

        # Fetch password from Keychain using -w flag to get just the password
        local password
        password=$(security find-generic-password -s "$service_name" -a "$account_name" -w 2>/dev/null || true)

        if [[ -n "$password" ]]; then
            # Escape any embedded double quotes in the value
            password="${password//\"/\\\"}"
            # Write as export statement with quoted value to preserve spaces
            echo "export ${account_name}=\"${password}\"" >> "$temp_output"
        fi
    done <<< "$accounts"

    # Move temp file to final location
    mkdir -p "$(dirname "$output_path")"
    mv "$temp_output" "$output_path"
    chmod 600 "$output_path"

    return 0
}
