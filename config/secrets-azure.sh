#!/usr/bin/env bash
# Secrets provider: Azure Key Vault
#
# Pulls secrets from Azure Key Vault using the az CLI.
# Requires az CLI to be installed and authenticated.
#
# Configuration (in .user-config.json):
#   secrets.azureVaultName: Name of the Azure Key Vault

set -euo pipefail

# Describe this provider for the setup menu
secrets_describe() {
    echo "Pull secrets from Azure Key Vault"
}

# Convert kebab-case to UPPER_SNAKE_CASE
# Used to convert Azure secret names to environment variable names
kebab_to_upper_snake() {
    local input="$1"
    # Replace hyphens with underscores and convert to uppercase
    echo "$input" | tr '[:lower:]' '[:upper:]' | tr '-' '_'
}

# Validate that az CLI is installed and authenticated, and vault is configured
# Returns 0 if valid, 1 if not (with error message to stderr)
secrets_validate() {
    # Check if az CLI is installed
    if ! command -v az &>/dev/null; then
        echo "error: az CLI not installed. Required for Azure Key Vault provider." >&2
        return 1
    fi

    # Check if az is authenticated
    if ! az account show >/dev/null 2>&1; then
        echo "error: az CLI not authenticated. Run: az login" >&2
        return 1
    fi

    # Read config file to get vault name
    if [[ ! -f "${USER_CONFIG:-.user-config.json}" ]]; then
        echo "error: user config file not found: ${USER_CONFIG:-.user-config.json}" >&2
        return 1
    fi

    # Extract vault name from config using jq
    local vault_name
    vault_name=$(jq -r '.secrets.azureVaultName // empty' "${USER_CONFIG:-.user-config.json}" 2>/dev/null)

    if [[ -z "$vault_name" ]]; then
        echo "error: secrets.azureVaultName not configured in user config" >&2
        return 1
    fi

    return 0
}

# Inject secrets from Azure Key Vault into $SECRETS_OUTPUT_PATH
# Lists secrets from vault, fetches each one, writes as export VAR=value
secrets_inject() {
    # Read config file to get vault name
    if [[ ! -f "${USER_CONFIG:-.user-config.json}" ]]; then
        echo "error: user config file not found: ${USER_CONFIG:-.user-config.json}" >&2
        return 1
    fi

    local vault_name
    vault_name=$(jq -r '.secrets.azureVaultName // empty' "${USER_CONFIG:-.user-config.json}" 2>/dev/null)

    if [[ -z "$vault_name" ]]; then
        echo "error: secrets.azureVaultName not configured in user config" >&2
        return 1
    fi

    # Ensure output path is set
    local output_path="${SECRETS_OUTPUT_PATH:-/home/claude/.secrets.env}"

    # Create temporary file to avoid partial writes
    local temp_output
    temp_output=$(mktemp)
    trap "rm -f '$temp_output'" RETURN

    # List secrets from vault
    local secret_names
    secret_names=$(az keyvault secret list --vault-name "$vault_name" --query "[].name" -o tsv 2>/dev/null)

    if [[ -z "$secret_names" ]]; then
        # No secrets found - create empty file
        mkdir -p "$(dirname "$output_path")"
        touch "$temp_output"
        mv "$temp_output" "$output_path"
        return 0
    fi

    # For each secret, fetch and write as export
    while IFS= read -r secret_name; do
        [[ -z "$secret_name" ]] && continue

        # Fetch secret value
        local secret_value
        secret_value=$(az keyvault secret show --vault-name "$vault_name" --name "$secret_name" --query "value" -o tsv 2>/dev/null)

        # Convert secret name from kebab-case to UPPER_SNAKE_CASE
        local env_var_name
        env_var_name=$(kebab_to_upper_snake "$secret_name")

        # Write as export statement
        echo "export ${env_var_name}=${secret_value}" >> "$temp_output"
    done <<< "$secret_names"

    # Move temp file to final location
    mkdir -p "$(dirname "$output_path")"
    mv "$temp_output" "$output_path"

    return 0
}
