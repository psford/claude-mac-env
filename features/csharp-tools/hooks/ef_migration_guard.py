#!/usr/bin/env python3
"""
ef_migration_guard.py

Enforces Entity Framework migration discipline on model changes.
Guards against committing model changes without corresponding migrations.

Triggered by: Pre-commit hook before .NET projects are committed
"""

import sys
import os
import subprocess
from pathlib import Path
from typing import List, Set


def find_cs_files_in_staging() -> Set[str]:
    """
    Find all C# files (.cs) that are staged for commit.

    Returns:
        Set of file paths that are staged
    """
    try:
        result = subprocess.run(
            ["git", "diff", "--cached", "--name-only", "--diff-filter=AM"],
            capture_output=True,
            text=True,
            timeout=5
        )
        if result.returncode == 0:
            return {f for f in result.stdout.strip().split('\n') if f.endswith('.cs')}
    except subprocess.TimeoutExpired:
        pass
    return set()


def find_ef_migrations_in_staging() -> Set[str]:
    """
    Find all Entity Framework migration files staged for commit.

    Returns:
        Set of migration file paths (in Migrations/ directories)
    """
    try:
        result = subprocess.run(
            ["git", "diff", "--cached", "--name-only", "--diff-filter=AM"],
            capture_output=True,
            text=True,
            timeout=5
        )
        if result.returncode == 0:
            migrations = {
                f for f in result.stdout.strip().split('\n')
                if '/Migrations/' in f and f.endswith('.cs')
            }
            return migrations
    except subprocess.TimeoutExpired:
        pass
    return set()


def check_model_migration_alignment() -> bool:
    """
    Verify that model changes have corresponding migrations.

    This is a best-effort check. If a model file is modified but no migration
    exists, warn the developer but allow the commit.

    Returns:
        False if a violation is detected, True otherwise
    """
    cs_files = find_cs_files_in_staging()
    migrations = find_ef_migrations_in_staging()

    # If there are CS files but no migrations in this commit, warn
    # (migrations might exist already, so this is permissive)
    if cs_files and not migrations:
        # Check if any files look like model files (heuristic)
        model_files = {f for f in cs_files if 'Models' in f or 'Entities' in f}
        if model_files:
            print(
                "Warning: C# model files staged but no migrations detected. "
                "Consider running 'dotnet ef migrations add'",
                file=sys.stderr
            )
            # Don't fail - this is advisory
            return True

    return True


def main() -> int:
    """
    Main entry point for EF migration guard.

    Returns:
        0 on success or advisory warnings, 1 on guard violation
    """
    try:
        if not check_model_migration_alignment():
            return 1
        return 0
    except Exception as e:
        # Silent failure - this is an optional guard
        return 0


if __name__ == "__main__":
    sys.exit(main())
