#!/usr/bin/env python3
"""
dotnet_process_guard.py

Monitors .NET process operations and enforces development discipline.
Guards against long-running or orphaned .NET processes that may consume resources.

Triggered by: Various git and development hooks
"""

import sys
import subprocess
import json
from typing import Optional


def get_dotnet_processes() -> list:
    """
    Retrieve list of currently running .NET processes.

    Returns:
        List of process information dictionaries
    """
    try:
        result = subprocess.run(
            ["dotnet", "process", "list"],
            capture_output=True,
            text=True,
            timeout=5
        )
        if result.returncode == 0:
            return json.loads(result.stdout) if result.stdout else []
    except (subprocess.TimeoutExpired, subprocess.CalledProcessError, json.JSONDecodeError):
        # Silent failure - process monitoring is optional
        pass
    return []


def check_process_health() -> bool:
    """
    Verify that active .NET processes are healthy.

    Returns:
        True if all processes are healthy, False otherwise
    """
    processes = get_dotnet_processes()

    # Monitor process count - warn if excessive
    if len(processes) > 10:
        print(f"Warning: {len(processes)} .NET processes running", file=sys.stderr)
        return False

    return True


def main() -> int:
    """
    Main entry point for .NET process guard.

    Returns:
        0 on success, 1 on guard violation
    """
    try:
        if not check_process_health():
            return 1
        return 0
    except Exception as e:
        # Silent failure - this is an optional guard
        return 0


if __name__ == "__main__":
    sys.exit(main())
