#!/usr/bin/env bash
# Secrets provider interface
#
# All secrets providers must implement these functions:
# - secrets_validate(): Check prerequisites are met (return 0 if valid, 1 if not)
# - secrets_inject(): Write secrets to $SECRETS_OUTPUT_PATH as export statements
# - secrets_describe(): Print one-line description of this provider
#
# This interface also provides:
# - SECRETS_OUTPUT_PATH: Default location for provider output
# - secrets_load(): Helper to source the secrets file in container

set -o pipefail

# Default output path for secrets (overridable)
export SECRETS_OUTPUT_PATH="${SECRETS_OUTPUT_PATH:-/home/claude/.secrets.env}"

# Load secrets from the output file if it exists
# Called from postCreateCommand to make secrets available in the shell
secrets_load() {
  if [[ -f "$SECRETS_OUTPUT_PATH" ]]; then
    # shellcheck disable=SC1090
    source "$SECRETS_OUTPUT_PATH"
    return 0
  fi
  return 0
}

# Error handling wrapper for provider operations
# Accepts provider name and operation name for clear error messages
# Usage: secrets_handle_error "provider_name" "operation_name" exit_code
secrets_handle_error() {
  local provider_name="$1"
  local operation="$2"
  local exit_code="$3"

  if [[ $exit_code -ne 0 ]]; then
    echo "error: secrets provider '$provider_name' failed during $operation (exit $exit_code)" >&2
    return 1
  fi
  return 0
}

# Validate that provider functions are implemented
# Usage: secrets_validate_interface
# Returns 0 if all required functions exist, 1 if missing
secrets_validate_interface() {
  local required_functions=("secrets_validate" "secrets_inject" "secrets_describe")
  local missing=0

  for func in "${required_functions[@]}"; do
    if ! declare -f "$func" > /dev/null; then
      echo "error: provider must implement '$func' function" >&2
      ((missing++))
    fi
  done

  if [[ $missing -gt 0 ]]; then
    return 1
  fi
  return 0
}
