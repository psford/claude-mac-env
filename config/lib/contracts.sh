#!/usr/bin/env bash
# contracts.sh — Shared design-by-contract assertion helpers for Layer 1 tools
#
# Every function:
#   - Returns 0 on success
#   - Returns 1 and writes error to stderr on failure
#   - Produces no UX output (no ✓, no progress messages)

set -euo pipefail

# Precondition: command exists on PATH
require_command() {
    local cmd="$1"
    if ! command -v "$cmd" &>/dev/null; then
        echo "precondition_failed: required command '$cmd' not found" >&2
        return 1
    fi
}

# Precondition: file exists and is readable
require_file() {
    local path="$1"
    if [ ! -f "$path" ]; then
        echo "precondition_failed: required file '$path' does not exist" >&2
        return 1
    fi
    if [ ! -r "$path" ]; then
        echo "precondition_failed: required file '$path' is not readable" >&2
        return 1
    fi
}

# Precondition: directory exists
require_dir() {
    local path="$1"
    if [ ! -d "$path" ]; then
        echo "precondition_failed: required directory '$path' does not exist" >&2
        return 1
    fi
}

# Precondition: environment variable is set and non-empty
require_env() {
    local var_name="$1"
    if [ -z "${!var_name:-}" ]; then
        echo "precondition_failed: required environment variable '$var_name' is not set or empty" >&2
        return 1
    fi
}

# Precondition: stdin is a TTY (for interactive prompts)
require_tty() {
    if [ ! -t 0 ]; then
        echo "precondition_failed: stdin is not a TTY — interactive prompt not available" >&2
        return 1
    fi
}

# Postcondition: file was created
ensure_file_exists() {
    local path="$1"
    if [ ! -f "$path" ]; then
        echo "postcondition_failed: expected file '$path' to exist but it does not" >&2
        return 1
    fi
}

# Postcondition: file is valid JSON
ensure_valid_json() {
    local path="$1"
    if [ ! -f "$path" ]; then
        echo "postcondition_failed: cannot validate JSON — file '$path' does not exist" >&2
        return 1
    fi
    if ! jq . "$path" >/dev/null 2>&1; then
        echo "postcondition_failed: file '$path' is not valid JSON" >&2
        return 1
    fi
}

# Postcondition: command exits 0
ensure_exit_zero() {
    local description="$1"
    shift
    if ! "$@" >/dev/null 2>&1; then
        echo "postcondition_failed: '$description' did not exit 0" >&2
        return 1
    fi
}
