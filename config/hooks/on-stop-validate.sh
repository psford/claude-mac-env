#!/usr/bin/env bash
# Stop hook — runs dependency validation before Claude can end the session.
# If dependencies are broken, blocks the stop.

VALIDATOR="/workspaces/claude-mac-env/config/validate-dependencies.sh"

if [ ! -f "$VALIDATOR" ]; then
  echo '{}'
  exit 0
fi

result=$(bash "$VALIDATOR" 2>&1)
rc=$?

if [ $rc -ne 0 ]; then
  errors=$(echo "$result" | grep 'FAILED:' | head -1)
  echo "{\"decision\":\"block\",\"reason\":\"Cannot end session with broken dependencies. ${errors}. Fix them or explain to the user what is still broken.\"}"
else
  echo '{}'
fi
