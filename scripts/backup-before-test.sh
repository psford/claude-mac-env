#!/bin/bash
# Run this on your Mac BEFORE testing bootstrap-v2
# Creates timestamped backups of everything that matters

set -euo pipefail

BACKUP_DIR="$HOME/.claude-mac-env-backup-$(date +%Y%m%d-%H%M%S)"
mkdir -p "$BACKUP_DIR"

echo "Backing up to: $BACKUP_DIR"

# Back up devcontainer config
if [ -f .devcontainer/devcontainer.json ]; then
    cp .devcontainer/devcontainer.json "$BACKUP_DIR/"
    echo "  ✓ devcontainer.json"
fi

if [ -f .devcontainer/devcontainer.json.template ]; then
    cp .devcontainer/devcontainer.json.template "$BACKUP_DIR/"
    echo "  ✓ devcontainer.json.template"
fi

# Back up user config
if [ -f .user-config.json ]; then
    cp .user-config.json "$BACKUP_DIR/"
    echo "  ✓ .user-config.json"
fi

echo ""
echo "Backup complete: $BACKUP_DIR"
echo "To restore: bash scripts/restore-from-backup.sh $BACKUP_DIR"
