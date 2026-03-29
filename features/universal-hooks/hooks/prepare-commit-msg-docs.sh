#!/bin/bash
# prepare-commit-msg-docs.sh — Reminds to update documentation
# Triggers when modifying public APIs or exported functions
# Exit 0 on success, non-zero to block
# Use --no-verify to bypass

set -e

# Get the commit message file
COMMIT_MSG_FILE="$1"

# Get list of staged files
STAGED_FILES=$(git diff --cached --name-only --diff-filter=ACM)

# Patterns that indicate API/public export changes
API_PATTERNS=(
    "export"           # JavaScript/TypeScript exports
    "public "          # Java/C# public methods
    "def "             # Python function definitions at module level
    "func "            # Go function exports
    "@api"             # Docstring annotations
    "interface "       # TypeScript/Java interfaces
    "class "           # Class definitions
)

DOCS_PATTERNS=(
    "README"
    "CHANGELOG"
    "docs"
    ".md"
)

# Check if any staged files contain API/public changes
API_MODIFIED=0
DOCS_MODIFIED=0

for file in $STAGED_FILES; do
    if [ -f "$file" ]; then
        # Check for API changes
        if [ "${file##*.}" = "ts" ] || [ "${file##*.}" = "js" ] || \
           [ "${file##*.}" = "py" ] || [ "${file##*.}" = "go" ] || \
           [ "${file##*.}" = "java" ]; then
            for pattern in "${API_PATTERNS[@]}"; do
                if git diff --cached "$file" | grep -q "^+.*$pattern"; then
                    API_MODIFIED=1
                    break
                fi
            done
        fi

        # Check if docs were modified
        for doc_pattern in "${DOCS_PATTERNS[@]}"; do
            if [[ "$file" =~ $doc_pattern ]]; then
                DOCS_MODIFIED=1
                break
            fi
        done
    fi
done

# Warn if API changed but docs weren't modified
if [ $API_MODIFIED -eq 1 ] && [ $DOCS_MODIFIED -eq 0 ]; then
    echo "Warning: You've modified public APIs or exported functions."
    echo "Please consider updating documentation (README, CHANGELOG, or docs/)."
    echo ""
    echo "To bypass this check, use: git commit --no-verify"
    echo ""
fi

exit 0
