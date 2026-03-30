#!/bin/bash
# pre-commit-atomicity.sh — Validates commit atomicity
# Warns if commit touches too many unrelated files
# Exit 0 on success, non-zero to block
# Use --no-verify to bypass

set -e

# Get list of staged files
STAGED_FILES=$(git diff --cached --name-only --diff-filter=ACM)

# Skip if no files are staged
if [ -z "$STAGED_FILES" ]; then
    exit 0
fi

# Count files in this commit
FILE_COUNT=$(echo "$STAGED_FILES" | wc -l)

# Threshold for "too many" files (warning threshold)
FILE_THRESHOLD=10

# Check file extensions to detect unrelated changes
declare -A EXTENSIONS
while IFS= read -r file; do
    # Extract extension
    ext="${file##*.}"
    if [ -z "$ext" ] || [ "$ext" = "$file" ]; then
        ext="(no extension)"
    fi
    ((EXTENSIONS["$ext"]++))
done <<< "$STAGED_FILES"

# Count distinct extensions
EXTENSION_COUNT=0
for ext in "${!EXTENSIONS[@]}"; do
    ((EXTENSION_COUNT++))
done

# Warn if commit touches many unrelated files
if [ "$FILE_COUNT" -gt "$FILE_THRESHOLD" ]; then
    echo "Warning: This commit touches $FILE_COUNT files (threshold: $FILE_THRESHOLD)"
    echo ""
    echo "Breakdown by file type:"
    for ext in $(printf '%s\n' "${!EXTENSIONS[@]}" | sort); do
        echo "  $ext: ${EXTENSIONS[$ext]} file(s)"
    done
    echo ""
    echo "Consider splitting this into multiple atomic commits."
    echo "To bypass this check, use: git commit --no-verify"
    echo ""
fi

# Warn if touching too many different file types
if [ $EXTENSION_COUNT -gt 3 ]; then
    echo "Warning: This commit touches $EXTENSION_COUNT different file types"
    echo "Consider grouping related changes together."
    echo "To bypass this check, use: git commit --no-verify"
    echo ""
fi

exit 0
