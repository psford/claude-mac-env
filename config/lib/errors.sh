#!/usr/bin/env bash
# errors.sh — Layer 2 error handling
#
# Accepts structured errors from Layer 1 tools. Returns recovery actions
# and plain-English user messages. Knows retry policy but NOT UX flow.
#
# Output format on stdout: action:message
#   action = retry | skip | abort
#
# All messages must pass the brother-in-law test: plain English, no jargon,
# actionable next steps.

set -euo pipefail

# Retry tracking — count per error type
declare -A ERROR_RETRY_COUNT

# Max retries per error type
declare -A ERROR_MAX_RETRIES=(
    [missing_tool]=0
    [gh_auth_error]=0
    [gh_login_failed]=3
    [az_auth_error]=0
    [az_login_failed]=3
    [gh_setup_git_failed]=1
    [clone_failed]=2
    [no_skills_found]=0
    [json_merge_failed]=0
    [symlink_failed]=0
    [secrets_failed]=0
)

# ── Per-type handlers ────────────────────────────────────────────────────────

handle_missing_tool() {
    local detail="$1"
    echo "abort:'${detail}' should be installed in the container image. Something is wrong with the Dockerfile."
}

handle_gh_auth_error() {
    local detail="$1"
    echo "abort:Unexpected error checking GitHub auth: ${detail}"
}

handle_gh_login_failed() {
    local count="${ERROR_RETRY_COUNT[gh_login_failed]:-0}"
    local max="${ERROR_MAX_RETRIES[gh_login_failed]}"
    if [ "$count" -le "$max" ]; then
        echo "retry:That didn't work. Common reasons: browser didn't open, network issue. Try again?"
    else
        echo "abort:No worries — run this command when you're ready: gh auth login --web --git-protocol https"
    fi
}

handle_az_auth_error() {
    local detail="$1"
    echo "abort:Unexpected error checking Azure auth: ${detail}"
}

handle_az_login_failed() {
    local count="${ERROR_RETRY_COUNT[az_login_failed]:-0}"
    local max="${ERROR_MAX_RETRIES[az_login_failed]}"
    if [ "$count" -le "$max" ]; then
        echo "retry:Azure login didn't work. Check your browser and try again?"
    else
        echo "abort:You can add Azure later by running: az login"
    fi
}

handle_gh_setup_git_failed() {
    local count="${ERROR_RETRY_COUNT[gh_setup_git_failed]:-0}"
    local max="${ERROR_MAX_RETRIES[gh_setup_git_failed]}"
    if [ "$count" -le "$max" ]; then
        echo "retry:"
    else
        echo "skip:Git credential helper couldn't be configured. git push may need manual auth."
    fi
}

handle_clone_failed() {
    local count="${ERROR_RETRY_COUNT[clone_failed]:-0}"
    local max="${ERROR_MAX_RETRIES[clone_failed]}"
    if [ "$count" -le "$max" ]; then
        echo "retry:Couldn't reach GitHub. Check your connection and try again?"
    else
        echo "abort:Still can't reach GitHub. Check your network and re-run bootstrap."
    fi
}

handle_no_skills_found() {
    echo "abort:Cloned the repo but found zero skills at plugins/*/skills/*/SKILL.md. Repository structure may have changed."
}

handle_json_merge_failed() {
    echo "abort:Settings file is corrupt — couldn't write valid JSON. Check ~/.claude/settings.json"
}

handle_symlink_failed() {
    echo "skip:gh symlink couldn't be created. This is non-critical — GitHub CLI may not be in your PATH."
}

handle_secrets_failed() {
    echo "skip:Secrets couldn't load. Your environment will work, but some features need credentials. Run 'bootstrap.sh --secrets-only' to try again later."
}

# ── Dispatch ─────────────────────────────────────────────────────────────────

# handle_error(error_type, detail, context)
# Routes to the appropriate handler. Tracks retry counts.
# Stdout: action:message
handle_error() {
    local error_type="$1"
    local detail="${2:-}"
    local _context="${3:-}"  # reserved for future per-step context

    # Increment retry count for this error type
    ((ERROR_RETRY_COUNT["$error_type"]=${ERROR_RETRY_COUNT["$error_type"]:-0}+1)) || true

    case "$error_type" in
        missing_tool)        handle_missing_tool "$detail" ;;
        gh_auth_error)       handle_gh_auth_error "$detail" ;;
        gh_login_failed)     handle_gh_login_failed ;;
        az_auth_error)       handle_az_auth_error "$detail" ;;
        az_login_failed)     handle_az_login_failed ;;
        gh_setup_git_failed) handle_gh_setup_git_failed ;;
        clone_failed)        handle_clone_failed ;;
        no_skills_found)     handle_no_skills_found ;;
        json_merge_failed)   handle_json_merge_failed ;;
        symlink_failed)      handle_symlink_failed ;;
        secrets_failed)      handle_secrets_failed ;;
        *)                   echo "abort:Unknown error: ${detail:-$error_type}" ;;
    esac
}
