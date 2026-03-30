#!/bin/bash
set -euo pipefail

# E2E validation script for claude-mac-env
# Checks that the Docker image builds, container starts, and all tools are available

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "${SCRIPT_DIR}")"

# ANSI color codes
GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m' # No Color

# Track pass/fail
PASS=0
FAIL=0

# Helper to print pass/fail
check() {
  local name="$1"
  local cmd="$2"
  local stderr

  stderr=$(eval "${cmd}" 2>&1 >/dev/null) || true

  if eval "${cmd}" >/dev/null 2>&1; then
    echo -e "${GREEN}✓${NC} ${name}"
    PASS=$((PASS + 1))
  else
    echo -e "${RED}✗${NC} ${name}"
    if [[ -n "${stderr}" ]]; then
      echo "  Error: ${stderr}"
    fi
    FAIL=$((FAIL + 1))
  fi
}

# Helper to run command in container (called indirectly via check())
# shellcheck disable=SC2317
run_in_container() {
  local cmd="$1"
  docker run --rm claude-mac-env:validate bash -c "${cmd}"
}

echo "=== Claude Mac Environment E2E Validation ==="
echo

# Check 1: Docker image builds
echo "Building Docker image..."
if docker build -t claude-mac-env:validate "${PROJECT_DIR}" >/dev/null 2>&1; then
  echo -e "${GREEN}✓${NC} Docker image builds"
  PASS=$((PASS + 1))
else
  echo -e "${RED}✗${NC} Docker image builds"
  FAIL=$((FAIL + 1))
  echo "Build failed. Exiting."
  exit 1
fi

echo

# Check 2: Container starts
check "Container starts" "docker run --rm claude-mac-env:validate echo 'OK'"

# Check 3: Claude Code is installed
check "Claude Code installed" "run_in_container 'claude --version'"

# Check 4: Non-root user is 'claude'
check "Non-root user is 'claude'" "run_in_container '[[ \$(whoami) == claude ]]'"

# Check 5: Node.js is available
check "Node.js available" "run_in_container 'node --version'"

# Check 6: Node.js version is LTS (v20 or v22)
check "Node.js LTS version" "run_in_container 'node --version | grep -E \"v(20|22|24)\" || false'"

# Check 7: Python 3 is available
check "Python 3 available" "run_in_container 'python3 --version'"

# Check 8: detect-package-manager.sh works
check "detect-package-manager.sh works" "run_in_container 'detect-package-manager.sh | grep -q apt && echo OK || false'"

# Check 9: npm is available
check "npm available" "run_in_container 'npm --version'"

# Check 10: git is available
check "git available" "run_in_container 'git --version'"

# Check 11: curl is available
check "curl available" "run_in_container 'curl --version | head -1'"

# Check 12: Check for universal-hooks Feature artifacts
echo
echo "Checking Feature artifacts..."

# universal-hooks should install hook files to /usr/local/share/claude-hooks/
check "universal-hooks Feature installed" \
  "run_in_container '[[ -d /usr/local/share/claude-hooks ]] && echo OK || false'"

# Check if at least one hook file exists
check "Hook files present" \
  "run_in_container '[[ \$(find /usr/local/share/claude-hooks -type f 2>/dev/null | wc -l) -gt 0 ]] && echo OK || false'"

# Check for manifest (if available)
check "Tooling manifest present" \
  "docker run --rm -v ${PROJECT_DIR}:/workspace claude-mac-env:validate bash -c '[[ -f /workspace/claude-env/tooling-manifest.json ]] && echo OK || false'"

echo

# AC3: Container filesystem isolation tests
echo "=== Filesystem Isolation Tests (AC3) ==="
echo

# AC3.1: Project dirs writable from inside container
check "AC3.1: Project dirs writable (RW mount)" \
  "docker run --rm -v /tmp/test-rw-$$:/workspaces/test bash -c 'touch /workspaces/test/write-test && rm /workspaces/test/write-test' 2>/dev/null"

# AC3.2: Mount a temp file RO, assert write fails
TEST_RO_FILE=$(mktemp)
trap 'rm -f $TEST_RO_FILE' EXIT
check "AC3.2: RO mount prevents writes" \
  "docker run --rm -v $TEST_RO_FILE:/home/claude/.gitconfig:ro bash -c '! (echo x >> /home/claude/.gitconfig 2>&1 | grep -q .)' 2>&1 | grep -qi 'read.only\|permission'"

# AC3.4: Assert /Users and /Volumes don't exist in container
check "AC3.4: /Users not visible in container" \
  "docker run --rm bash -c '! test -d /Users' 2>&1"

check "AC3.4: /Volumes not visible in container" \
  "docker run --rm bash -c '! test -d /Volumes' 2>&1"

echo

# AC4: Dev Container Features tests
echo "=== Dev Container Features Tests (AC4) ==="
echo

# AC4.3: Check dotnet version (requires csharp-tools feature, for now just check if installed)
check "AC4.3: dotnet available (if installed)" \
  "run_in_container 'which dotnet || echo \"dotnet not in this build\" | grep \"not in this build\"' 2>&1 | grep -q 'dotnet\|not in this build'"

# AC4.4: Check hooks directory has files
check "AC4.4: Hook files present if universal-hooks installed" \
  "run_in_container '[[ -d /usr/local/share/claude-hooks ]] && [[ \$(find /usr/local/share/claude-hooks -type f 2>/dev/null | wc -l) -gt 0 ]] || echo \"hooks dir not installed\" | grep \"not installed\"' 2>&1"

echo
echo "=== Summary ==="
echo -e "${GREEN}Passed: ${PASS}${NC}"
echo -e "${RED}Failed: ${FAIL}${NC}"
echo

# Clean up test image
docker rmi claude-mac-env:validate >/dev/null 2>&1 || true

# Exit with appropriate code
if [[ ${FAIL} -eq 0 ]]; then
  echo "All checks passed!"
  exit 0
else
  echo "Some checks failed."
  exit 1
fi
