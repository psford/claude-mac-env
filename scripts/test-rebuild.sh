#!/bin/bash
# test-rebuild.sh — Full E2E test: back up, rebuild container, verify, rollback on failure
#
# Run this on your Mac from the claude-mac-env repo directory.
# It will:
#   1. Back up current config
#   2. Switch to bootstrap-v2 branch
#   3. Run setup.sh to generate new devcontainer.json
#   4. Prompt you to rebuild the container in VS Code
#   5. After rebuild, verify everything works
#   6. If anything fails, offer rollback
#
# Usage: bash scripts/test-rebuild.sh

set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_DIR"

BACKUP_DIR="$HOME/.claude-mac-env-backup-$(date +%Y%m%d-%H%M%S)"
ORIGINAL_BRANCH=""

# ── Helpers ──────────────────────────────────────────────────────────────────

info()    { echo "ℹ  $*"; }
success() { echo "✓  $*"; }
error()   { echo "✗  $*" >&2; }
warn()    { echo "⚠  $*" >&2; }

rollback() {
    echo ""
    error "Something went wrong. Rolling back..."
    echo ""

    # Restore config files
    if [ -d "$BACKUP_DIR" ]; then
        for file in devcontainer.json devcontainer.json.template; do
            if [ -f "$BACKUP_DIR/$file" ]; then
                cp "$BACKUP_DIR/$file" .devcontainer/"$file" 2>/dev/null || true
            fi
        done
        if [ -f "$BACKUP_DIR/.user-config.json" ]; then
            cp "$BACKUP_DIR/.user-config.json" ./.user-config.json
        fi
        success "Config files restored from backup"
    fi

    # Switch back to original branch
    if [ -n "$ORIGINAL_BRANCH" ] && [ "$ORIGINAL_BRANCH" != "bootstrap-v2" ]; then
        git checkout "$ORIGINAL_BRANCH" 2>/dev/null || true
        success "Switched back to $ORIGINAL_BRANCH"
    fi

    echo ""
    echo "Backup is at: $BACKUP_DIR"
    echo "Rebuild the container in VS Code to restore your previous environment."
    echo ""
}

# ── Step 1: Pre-flight checks ───────────────────────────────────────────────

echo ""
echo "══════════════════════════════════════════════════════"
echo "  Bootstrap v2 — Full Rebuild Test"
echo "══════════════════════════════════════════════════════"
echo ""

# Check we're in the right directory
if [ ! -f "setup.sh" ] || [ ! -d "features" ]; then
    error "Run this from the claude-mac-env repo directory."
    exit 1
fi

# Check for uncommitted changes
if ! git diff --quiet 2>/dev/null || ! git diff --cached --quiet 2>/dev/null; then
    warn "You have uncommitted changes. Commit or stash them first."
    git status --short
    echo ""
    read -rp "Continue anyway? (type 'yes'): " confirm
    if [ "$confirm" != "yes" ]; then
        echo "Aborted."
        exit 1
    fi
fi

ORIGINAL_BRANCH=$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "")
info "Current branch: $ORIGINAL_BRANCH"

# ── Step 2: Back up ─────────────────────────────────────────────────────────

info "Backing up to: $BACKUP_DIR"
mkdir -p "$BACKUP_DIR"

for file in .devcontainer/devcontainer.json .devcontainer/devcontainer.json.template .user-config.json; do
    if [ -f "$file" ]; then
        cp "$file" "$BACKUP_DIR/$(basename "$file")"
        echo "  ✓ $(basename "$file")"
    fi
done

# Also save the branch name
echo "$ORIGINAL_BRANCH" > "$BACKUP_DIR/original-branch.txt"
success "Backup complete"

# ── Step 3: Switch to bootstrap-v2 ──────────────────────────────────────────

echo ""
if [ "$ORIGINAL_BRANCH" = "bootstrap-v2" ]; then
    info "Already on bootstrap-v2"
    git pull --ff-only 2>/dev/null || true
else
    info "Switching to bootstrap-v2..."
    git fetch origin
    git checkout bootstrap-v2 || {
        error "Failed to switch to bootstrap-v2"
        rollback
        exit 1
    }
fi

# ── Step 4: Run setup.sh ────────────────────────────────────────────────────

echo ""
info "Running setup.sh..."
echo ""

if ! bash setup.sh; then
    error "setup.sh failed"
    rollback
    exit 1
fi

# Verify the generated devcontainer.json is valid
if [ -f ".devcontainer/devcontainer.json" ]; then
    if jq . .devcontainer/devcontainer.json >/dev/null 2>&1; then
        success "Generated devcontainer.json is valid JSON"
    else
        error "Generated devcontainer.json is INVALID JSON"
        rollback
        exit 1
    fi
else
    error "No devcontainer.json was generated"
    rollback
    exit 1
fi

# ── Step 5: Prompt for container rebuild ─────────────────────────────────────

echo ""
echo "══════════════════════════════════════════════════════"
echo "  Ready to rebuild the container."
echo ""
echo "  In VS Code:"
echo "    Cmd+Shift+P → 'Dev Containers: Rebuild Container'"
echo ""
echo "  After the container rebuilds, bootstrap.sh will run"
echo "  automatically as postCreateCommand."
echo ""
echo "  When the container is up, open a terminal inside it"
echo "  and run:"
echo ""
echo "    bash /workspaces/claude-mac-env/scripts/verify-rebuild.sh"
echo ""
echo "══════════════════════════════════════════════════════"
echo ""
echo "Backup location: $BACKUP_DIR"
echo ""
echo "If anything breaks, restore with:"
echo "  bash scripts/restore-from-backup.sh $BACKUP_DIR"
echo "  git checkout $ORIGINAL_BRANCH"
echo "  Then rebuild the container again."
echo ""
