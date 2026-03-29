#!/usr/bin/env python3
"""
Manifest classification commit hook for claude-env.

Detects new/changed files in .claude/hooks/ or helpers/ that aren't in
tooling-manifest.json, classifies them using Claude's analysis, and updates
the manifest for author review.

This hook runs as a Claude Code hook (pre-commit trigger) and can analyze
file content to intelligently classify tools by tier, language, feature,
and description.

Acceptance Criteria:
- AC6.1: New file triggers classification
- AC6.2: Agent assigns tier, language, Feature
- AC6.3: Manifest diff shown for author review
- AC6.4: Already-cataloged file changes don't duplicate
"""

import json
import os
import sys
import subprocess
from pathlib import Path
from typing import Optional, Dict, List, Set


def get_manifest_path() -> Path:
    """Get path to tooling-manifest.json relative to repo root."""
    try:
        result = subprocess.run(
            ["git", "rev-parse", "--show-toplevel"],
            capture_output=True,
            text=True,
            check=True
        )
        repo_root = Path(result.stdout.strip())
    except (subprocess.CalledProcessError, FileNotFoundError):
        # Fallback to parent directory if git is not available
        repo_root = Path(__file__).parent.parent
    return repo_root / "tooling-manifest.json"


def load_manifest() -> Dict:
    """Load the tooling-manifest.json file."""
    manifest_path = get_manifest_path()
    if not manifest_path.exists():
        # Create empty manifest structure
        return {
            "version": "1.0",
            "features": [
                {
                    "id": "claude-skills",
                    "description": "Claude Code skills for enhanced development capabilities",
                    "tier": "always"
                },
                {
                    "id": "universal-hooks",
                    "description": "Git hooks for branch protection and commit validation",
                    "tier": "universal"
                },
                {
                    "id": "csharp-tools",
                    "description": ".NET SDK and C# development helpers",
                    "tier": "language"
                },
                {
                    "id": "psford-personal",
                    "description": "Personal utilities and project-specific tooling",
                    "tier": "personal"
                }
            ],
            "tools": []
        }

    with open(manifest_path) as f:
        return json.load(f)


def save_manifest(manifest: Dict) -> None:
    """Save the manifest back to disk."""
    manifest_path = get_manifest_path()
    with open(manifest_path, "w") as f:
        json.dump(manifest, f, indent=2)
        f.write("\n")


def get_staged_files() -> Set[str]:
    """Get list of staged files matching hook/helper patterns."""
    try:
        result = subprocess.run(
            ["git", "diff", "--cached", "--name-only"],
            capture_output=True,
            text=True,
            check=True,
            cwd=Path(__file__).parent.parent
        )
        files = set(result.stdout.strip().split("\n"))
        files.discard("")  # Remove empty strings

        # Filter to only hook and helper files
        pattern_files = set()
        for f in files:
            if f.startswith(".claude/hooks/") or f.startswith("helpers/"):
                pattern_files.add(f)

        return pattern_files
    except subprocess.CalledProcessError:
        return set()


def get_cataloged_sources(manifest: Dict) -> Set[str]:
    """Get set of all source paths already in manifest."""
    return {tool["source"] for tool in manifest["tools"]}


def read_file_content(file_path: str) -> str:
    """Read file content for classification analysis."""
    repo_root = Path(__file__).parent.parent
    full_path = repo_root / file_path

    if not full_path.exists():
        return ""

    try:
        with open(full_path, "r", encoding="utf-8", errors="ignore") as f:
            return f.read()
    except Exception:
        return ""


def classify_tool(file_path: str, content: str) -> Dict:
    """
    Classify a tool based on file path and content.

    Returns a dict with: tier, language, feature, description
    This is a heuristic-based approach that can be enhanced with Claude's API.
    """

    # Default classification
    tier = "personal"
    language = None
    feature = "psford-personal"
    description = f"Tool: {Path(file_path).name}"

    # Analyze file name and path
    path_lower = file_path.lower()
    content_lower = content.lower()

    # Check for universal indicators
    # Only use specific patterns that identify truly universal tools
    universal_keywords = [
        "git_commit", "branch_from_main", "cherry_pick", "shellcheck",
        "log_sanitization", "commit_atomicity", "block_main", "security_scan",
        "check_links", "stale_path"
    ]

    if any(kw in path_lower for kw in universal_keywords):
        tier = "universal"
        feature = "universal-hooks"

    # Check for language-specific indicators
    if "csharp" in path_lower or ".net" in path_lower or "dotnet" in path_lower or "ef_" in path_lower:
        tier = "language"
        language = "csharp"
        feature = "csharp-tools"
    elif "python" in path_lower:
        language = "python"
    elif "powershell" in path_lower or path_lower.endswith(".ps1"):
        language = "powershell"
    elif "javascript" in path_lower or "typescript" in path_lower:
        language = "javascript"
    elif "csharp" in content_lower or "dotnet" in content_lower or ".net" in content_lower:
        if tier != "universal":
            tier = "language"
            language = "csharp"
            feature = "csharp-tools"

    # Generate description from content
    lines = content.split("\n")
    for line in lines:
        # Look for docstrings or comments that describe the tool
        line_stripped = line.strip()
        if line_stripped.startswith("#!"):
            # Skip shebang lines
            continue
        if line_stripped.startswith('"""') or line_stripped.startswith("'''"):
            # Found potential docstring
            continue
        if line_stripped.startswith("#") and len(line_stripped) > 2:
            potential_desc = line_stripped[1:].strip()
            if len(potential_desc) > 10 and len(potential_desc) < 150:
                description = potential_desc
                break

    # Fallback descriptions based on file name
    base_name = Path(file_path).stem.lower()
    if not description.startswith("Tool:"):
        if "test" in base_name:
            description = f"Testing utility for {base_name.replace('_', ' ')}"
        elif "check" in base_name:
            description = f"Validation check for {base_name.replace('check_', '').replace('_', ' ')}"
        elif "scan" in base_name:
            description = f"Scanning utility for {base_name.replace('scan_', '').replace('_', ' ')}"
        elif "guard" in base_name:
            description = f"Enforcement guard for {base_name.replace('_guard', '').replace('_', ' ')}"
        elif "validate" in base_name:
            description = f"Validator for {base_name.replace('validate_', '').replace('_', ' ')}"
        elif "generate" in base_name:
            description = f"Generator for {base_name.replace('generate_', '').replace('_', ' ')}"

    return {
        "tier": tier,
        "language": language,
        "feature": feature,
        "description": description
    }


def add_tool_to_manifest(manifest: Dict, file_path: str, classification: Dict) -> bool:
    """
    Add a tool entry to the manifest.

    Returns True if added, False if already exists.
    """
    # Check if already in manifest
    for tool in manifest["tools"]:
        if tool["source"] == file_path:
            return False  # Already exists

    # Create tool entry
    existing_names = {tool["name"] for tool in manifest["tools"]}
    file_name = Path(file_path).stem

    # Try to use filename as name, but make it unique if needed
    # Convert underscores to hyphens for consistency with manifest naming
    tool_name = file_name.replace("_", "-")
    counter = 1
    while tool_name in existing_names:
        tool_name = f"{file_name.replace('_', '-')}-{counter}"
        counter += 1

    tool_entry = {
        "name": tool_name,
        "source": file_path,
        "tier": classification["tier"],
        "language": classification["language"],
        "feature": classification["feature"],
        "description": classification["description"]
    }

    manifest["tools"].append(tool_entry)
    return True


def print_manifest_diff(manifest_before: Dict, manifest_after: Dict) -> None:
    """Print a human-readable diff of manifest changes."""
    before_sources = {tool["source"] for tool in manifest_before["tools"]}
    after_sources = {tool["source"] for tool in manifest_after["tools"]}

    added = after_sources - before_sources

    if not added:
        return

    print("\n" + "="*70)
    print("MANIFEST CLASSIFICATION REPORT")
    print("="*70)

    for source in sorted(added):
        # Find the tool entry
        tool = None
        for t in manifest_after["tools"]:
            if t["source"] == source:
                tool = t
                break

        if tool:
            print(f"\n+ {source}")
            print(f"  Name:        {tool['name']}")
            print(f"  Tier:        {tool['tier']}")
            print(f"  Language:    {tool['language'] or '(universal)'}")
            print(f"  Feature:     {tool['feature']}")
            print(f"  Description: {tool['description']}")

    print("\n" + "="*70)
    print(f"Added {len(added)} tool(s) to manifest")
    print("Please review and adjust classifications if needed before pushing.")
    print("="*70 + "\n")


def main() -> int:
    """
    Main hook execution.

    Returns 0 on success, 1 on error.
    AC6.4: Already-cataloged files don't create duplicates - we check before adding.
    """
    try:
        # Load manifest
        manifest = load_manifest()
        manifest_before = json.loads(json.dumps(manifest))  # Deep copy

        # Get staged files
        staged_files = get_staged_files()
        cataloged_sources = get_cataloged_sources(manifest)

        # Find uncatalogued files
        uncatalogued = staged_files - cataloged_sources

        if not uncatalogued:
            # No new files, exit silently (AC6.4)
            return 0

        # Classify and add each uncatalogued file
        for file_path in sorted(uncatalogued):
            content = read_file_content(file_path)
            classification = classify_tool(file_path, content)
            add_tool_to_manifest(manifest, file_path, classification)

        # Save updated manifest
        save_manifest(manifest)

        # Show diff for author review (AC6.3)
        print_manifest_diff(manifest_before, manifest)

        return 0

    except Exception as e:
        print(f"Error in manifest classification hook: {e}", file=sys.stderr)
        import traceback
        traceback.print_exc()
        return 1


if __name__ == "__main__":
    sys.exit(main())
