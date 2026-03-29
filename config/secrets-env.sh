#!/usr/bin/env bash
# Secrets provider: .env file reader
#
# Reads secrets from a .env file on the Mac host, mounted into the container.
# Environment variables can be stored with or without "export" prefix.
# Comments and empty lines are skipped.
#
# Configuration (in .user-config.json):
#   secrets.envFilePath: Path to the .env file on the host

set -euo pipefail

# Describe this provider for the setup menu
secrets_describe() {
    echo "Read secrets from a .env file on the Mac"
}

# Validate that the configured .env file exists and is readable
# Returns 0 if valid, 1 if not (with error message to stderr)
secrets_validate() {
    # Read config file to get env file path
    if [[ ! -f "${USER_CONFIG:-.user-config.json}" ]]; then
        echo "error: user config file not found: ${USER_CONFIG:-.user-config.json}" >&2
        return 1
    fi

    # Extract envFilePath from config using jq
    local env_file_path
    env_file_path=$(jq -r '.secrets.envFilePath // empty' "${USER_CONFIG:-.user-config.json}" 2>/dev/null)

    if [[ -z "$env_file_path" ]]; then
        echo "error: secrets.envFilePath not configured in user config" >&2
        return 1
    fi

    # Check if file exists and is readable
    if [[ ! -f "$env_file_path" ]]; then
        echo "error: .env file not found at path: $env_file_path" >&2
        return 1
    fi

    if [[ ! -r "$env_file_path" ]]; then
        echo "error: .env file is not readable: $env_file_path" >&2
        return 1
    fi

    return 0
}

# Inject secrets into $SECRETS_OUTPUT_PATH
# Converts .env file contents to export format
# Skips comments and empty lines
secrets_inject() {
    # Read config file to get env file path
    if [[ ! -f "${USER_CONFIG:-.user-config.json}" ]]; then
        echo "error: user config file not found: ${USER_CONFIG:-.user-config.json}" >&2
        return 1
    fi

    local env_file_path
    env_file_path=$(jq -r '.secrets.envFilePath // empty' "${USER_CONFIG:-.user-config.json}" 2>/dev/null)

    if [[ -z "$env_file_path" ]]; then
        echo "error: secrets.envFilePath not configured in user config" >&2
        return 1
    fi

    # Ensure output path is set
    local output_path="${SECRETS_OUTPUT_PATH:-/home/claude/.secrets.env}"

    # Create temporary file to avoid partial writes
    local temp_output
    temp_output=$(mktemp)
    trap "rm -f '$temp_output'" RETURN

    # Process .env file: convert to export format, skip comments and empty lines
    while IFS= read -r line; do
        # Skip empty lines
        [[ -z "$line" ]] && continue

        # Skip comment lines
        [[ "$line" =~ ^[[:space:]]*# ]] && continue

        # Skip lines that are only whitespace
        [[ "$line" =~ ^[[:space:]]*$ ]] && continue

        # If line doesn't start with "export", add it
        if [[ ! "$line" =~ ^[[:space:]]*export[[:space:]] ]]; then
            line="export $line"
        fi

        echo "$line" >> "$temp_output"
    done < "$env_file_path"

    # Move temp file to final location
    mkdir -p "$(dirname "$output_path")"
    mv "$temp_output" "$output_path"

    return 0
}
