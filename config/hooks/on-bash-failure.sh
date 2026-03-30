#!/usr/bin/env bash
# PostToolUseFailure hook for Bash — blocks Claude from silently moving on
# after a failed command. Forces acknowledgment to the user.

INPUT=$(cat)
CMD=$(echo "$INPUT" | jq -r '.tool_input.command // "unknown"')
EXIT_CODE=$(echo "$INPUT" | jq -r '.tool_response.exitCode // "unknown"')

echo "{\"decision\":\"block\",\"reason\":\"Bash command failed (exit ${EXIT_CODE}). Command: ${CMD}. You MUST explain this failure to the user and get direction before continuing. Do NOT silently move on.\"}"
