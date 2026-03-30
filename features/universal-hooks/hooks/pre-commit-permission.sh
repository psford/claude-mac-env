#!/bin/bash
# pre-commit-permission.sh — Asks for explicit confirmation before committing
# Claude Code commit discipline hook
# Exit 0 on success, non-zero to block
# Use --no-verify to bypass

set -e

# Skip in non-interactive contexts (CI, automated processes)
if [ ! -t 0 ]; then
    exit 0
fi

# Get list of staged files
STAGED_FILES=$(git diff --cached --name-only --diff-filter=ACM)
FILE_COUNT=$(echo "$STAGED_FILES" | wc -l)

# Get the commit message (from COMMIT_EDITMSG if available)
COMMIT_MSG_FILE="${1:-.git/COMMIT_EDITMSG}"

if [ ! -f "$COMMIT_MSG_FILE" ]; then
    # No commit message yet, proceed
    exit 0
fi

# Read commit message (first non-comment line)
COMMIT_MSG=$(grep -v '^#' "$COMMIT_MSG_FILE" | head -1 | tr -d '\n')

# Show summary
echo ""
echo "About to commit:"
echo "  Files: $FILE_COUNT"
echo "  Message: $COMMIT_MSG"
echo ""

# Get list of files to be committed
if [ "$FILE_COUNT" -le 5 ]; then
    echo "Files being committed:"
    # shellcheck disable=SC2001
    echo "$STAGED_FILES" | sed 's/^/    /'
else
    echo "Files being committed (first 5 of $FILE_COUNT):"
    echo "$STAGED_FILES" | head -5 | sed 's/^/    /'
    echo "    ... and $((FILE_COUNT - 5)) more files"
fi

echo ""
echo "To bypass this check, use: git commit --no-verify"
read -rp "Proceed with commit? (type 'yes' to confirm): " confirm

if [ "$confirm" != "yes" ]; then
    echo "Commit cancelled."
    exit 1
fi

exit 0
