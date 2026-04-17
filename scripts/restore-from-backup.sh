#!/bin/bash
# Restores from a backup created by backup-before-test.sh
# Usage: bash scripts/restore-from-backup.sh ~/.claude-mac-env-backup-YYYYMMDD-HHMMSS

set -euo pipefail

BACKUP_DIR="${1:?Usage: $0 <backup-directory>}"

if [ ! -d "$BACKUP_DIR" ]; then
    echo "ERROR: Backup directory not found: $BACKUP_DIR"
    exit 1
fi

echo "Restoring from: $BACKUP_DIR"

for file in devcontainer.json devcontainer.json.template .user-config.json; do
    if [ -f "$BACKUP_DIR/$file" ]; then
        if [ "$file" = ".user-config.json" ]; then
            cp "$BACKUP_DIR/$file" ./"$file"
        else
            cp "$BACKUP_DIR/$file" .devcontainer/"$file"
        fi
        echo "  ✓ $file"
    fi
done

echo ""
echo "Restored. Rebuild your container to apply."
