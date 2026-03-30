#!/bin/bash
# pre-commit-log-sanitize.sh — Checks staged files for CWE-117 log injection patterns
# Warns on suspicious log statements
# Exit 0 on success, non-zero to block
# Use --no-verify to bypass

set -e

# Get list of staged files
STAGED_FILES=$(git diff --cached --name-only --diff-filter=ACM)

# Patterns to detect (CWE-117 log injection)
# These are warning patterns, not necessarily blocking
# shellcheck disable=SC2016
LOG_INJECTION_PATTERNS=(
    'logger\..*\(\$'           # Variable interpolation in logger calls
    'console\.log\(\$'         # Variable in console.log
    'print\(\$'                # Variable in print
    'echo.*\$\{'               # Variable in echo (template literals and expansions)
    'log\..*\(\`.*\$\{.*\}\`' # Template literals with variables
)

SUSPICIOUS_FOUND=0

for file in $STAGED_FILES; do
    if [ -f "$file" ]; then
        for pattern in "${LOG_INJECTION_PATTERNS[@]}"; do
            if grep -n "$pattern" "$file" > /dev/null 2>&1; then
                if [ $SUSPICIOUS_FOUND -eq 0 ]; then
                    echo "Warning: Potential CWE-117 log injection patterns detected:"
                    echo ""
                    SUSPICIOUS_FOUND=1
                fi
                echo "File: $file"
                grep -n "$pattern" "$file" | sed 's/^/  /'
                echo ""
            fi
        done
    fi
done

if [ $SUSPICIOUS_FOUND -eq 1 ]; then
    echo "Please review the above patterns for log injection vulnerabilities."
    echo "To bypass this check, use: git commit --no-verify"
    echo ""
fi

exit 0
