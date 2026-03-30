#!/usr/bin/env bash
# Bootstrap secrets in container during postCreateCommand
#
# This script:
# 1. Reads the selected secrets provider from .user-config.json
# 2. Sources the interface and provider scripts
# 3. Validates the provider is configured correctly
# 4. Injects secrets into $SECRETS_OUTPUT_PATH
# 5. Sources the secrets to make them available in current shell
#
# If no provider is configured, prints informational message and exits cleanly

set -o pipefail

# Script directory for sourcing other scripts
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Validate dependencies before doing anything
if [[ -f "$SCRIPT_DIR/validate-dependencies.sh" ]]; then
  # shellcheck disable=SC1091
  source "$SCRIPT_DIR/validate-dependencies.sh"
  echo ""
  echo "=== Pre-bootstrap dependency check ==="
  validate_chain_core
  validate_chain_secrets
  if [[ $VALIDATION_ERRORS -gt 0 ]]; then
    echo ""
    echo "ERROR: $VALIDATION_ERRORS missing dependencies. Bootstrap cannot proceed."
    echo "Run: bash $SCRIPT_DIR/validate-dependencies.sh  (for full report)"
    exit 1
  fi
fi

# User config file path (mounted from host at /workspaces/.claude-mac-env/.user-config.json)
# Fall back to parent directory if not found at mounted location
USER_CONFIG="${USER_CONFIG:-/workspaces/.claude-mac-env/.user-config.json}"
if [[ ! -f "$USER_CONFIG" ]]; then
  USER_CONFIG=".user-config.json"
fi

# Source the interface to get helper functions and defaults
if [[ ! -f "$SCRIPT_DIR/secrets-interface.sh" ]]; then
  echo "warning: secrets interface not found at $SCRIPT_DIR/secrets-interface.sh" >&2
  exit 0
fi

# shellcheck disable=SC1090,SC1091
source "$SCRIPT_DIR/secrets-interface.sh"

# Read provider name from user config
# Returns empty string if not configured
get_provider_from_config() {
  if [[ ! -f "$USER_CONFIG" ]]; then
    return
  fi

  # Use jq to extract provider, but don't fail if jq not available
  if command -v jq &> /dev/null; then
    jq -r '.secrets.provider // empty' "$USER_CONFIG" 2>/dev/null || true
  fi
}

# Main bootstrap logic
main() {
  # Check for jq availability
  if ! command -v jq &>/dev/null; then
    echo "warning: jq is required but not installed" >&2
    echo "note: container startup continuing without secrets" >&2
    return 0
  fi

  local provider_name
  provider_name=$(get_provider_from_config)

  # No provider configured - this is valid, just exit cleanly
  if [[ -z "$provider_name" ]] || [[ "$provider_name" == "none" ]]; then
    echo "No secrets provider configured. Use setup.sh to configure one."
    return 0
  fi

  # Construct provider script path
  local provider_script="$SCRIPT_DIR/secrets-${provider_name}.sh"

  # Check provider script exists
  if [[ ! -f "$provider_script" ]]; then
    echo "warning: secrets provider script not found: $provider_script" >&2
    echo "note: container startup continuing without secrets" >&2
    return 0
  fi

  # Source the provider script
  # shellcheck disable=SC1090
  source "$provider_script" || {
    echo "warning: failed to source provider script: $provider_script" >&2
    return 0
  }

  # Validate that provider implements required interface
  if ! secrets_validate_interface; then
    echo "warning: provider $provider_name does not implement required interface" >&2
    return 0
  fi

  # Run provider validation
  if ! secrets_validate; then
    echo "warning: secrets provider validation failed for $provider_name" >&2
    echo "note: container startup continuing without secrets" >&2
    return 0
  fi

  # Inject secrets into output file
  if ! secrets_inject; then
    echo "warning: secrets provider injection failed for $provider_name" >&2
    echo "note: container startup continuing without secrets" >&2
    return 0
  fi

  # Load secrets into current shell
  secrets_load || {
    echo "warning: failed to load secrets from $SECRETS_OUTPUT_PATH" >&2
    return 0
  }

  return 0
}

# Run main function
main "$@"
