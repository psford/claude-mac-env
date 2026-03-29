#!/bin/bash
# pre-push-branch-guard.sh — Prevents direct push to main/master branches
# Prompts user to confirm if pushing to protected branch
# Exit 0 on success, non-zero to block
# Use --no-verify to bypass

set -e

# Skip in non-interactive contexts (CI, automated processes)
if [ ! -t 0 ]; then
    exit 0
fi

# Get the current branch
BRANCH=$(git rev-parse --abbrev-ref HEAD)

# Protected branches
PROTECTED_BRANCHES=("main" "master" "develop")

# Check if pushing to a protected branch
for protected in "${PROTECTED_BRANCHES[@]}"; do
    if [ "$BRANCH" = "$protected" ]; then
        echo "Warning: You are about to push to protected branch '$BRANCH'"
        echo ""
        echo "To bypass this check, use: git push --no-verify"
        read -p "Are you sure you want to push to '$BRANCH'? (type 'yes' to confirm): " confirm

        if [ "$confirm" != "yes" ]; then
            echo "Push cancelled."
            exit 1
        fi
        break
    fi
done

exit 0
