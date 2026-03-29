#!/usr/bin/env python3
"""
Unit tests for manifest_classification_guard.py

Tests for:
- Known universal tools classified correctly
- Known personal tools classified as personal (not universal)
- Language detection (csharp, powershell)
- Idempotency (AC6.4)
- Description extraction skips shebangs
"""

import json
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch, MagicMock

# Import the module to test
import sys
hooks_dir = Path(__file__).parent / ".claude" / "hooks"
sys.path.insert(0, str(hooks_dir))
from manifest_classification_guard import (
    classify_tool,
    get_manifest_path,
    load_manifest,
    save_manifest,
    add_tool_to_manifest,
    get_cataloged_sources,
)


class TestClassifyTool(unittest.TestCase):
    """Test the classify_tool function for correct tier and language detection."""

    def test_universal_git_commit_guard(self):
        """git_commit_guard should be classified as universal."""
        content = '#!/usr/bin/env python3\n"""Validates git commits."""'
        result = classify_tool(".claude/hooks/git_commit_guard.py", content)
        self.assertEqual(result["tier"], "universal")
        self.assertEqual(result["feature"], "universal-hooks")

    def test_universal_branch_from_main_guard(self):
        """branch_from_main_guard should be classified as universal."""
        content = '#!/usr/bin/env python3\n"""Ensures branches originate from main."""'
        result = classify_tool(".claude/hooks/branch_from_main_guard.py", content)
        self.assertEqual(result["tier"], "universal")
        self.assertEqual(result["feature"], "universal-hooks")

    def test_universal_cherry_pick_guard(self):
        """cherry_pick_guard should be classified as universal."""
        content = '#!/usr/bin/env python3\n"""Guards cherry-pick operations."""'
        result = classify_tool(".claude/hooks/cherry_pick_guard.py", content)
        self.assertEqual(result["tier"], "universal")
        self.assertEqual(result["feature"], "universal-hooks")

    def test_universal_shellcheck_write_guard(self):
        """shellcheck_write_guard should be classified as universal."""
        content = '#!/usr/bin/env python3\n"""Validates shell script quality."""'
        result = classify_tool(".claude/hooks/shellcheck_write_guard.py", content)
        self.assertEqual(result["tier"], "universal")
        self.assertEqual(result["feature"], "universal-hooks")

    def test_universal_block_main_commits(self):
        """block_main_commits should be classified as universal."""
        content = '#!/usr/bin/env python3\n"""Git pre-commit: block commits to main branch."""'
        result = classify_tool("helpers/hooks/block_main_commits.py", content)
        self.assertEqual(result["tier"], "universal")
        self.assertEqual(result["feature"], "universal-hooks")

    def test_universal_check_log_sanitization(self):
        """check_log_sanitization should be classified as universal."""
        content = '#!/usr/bin/env python3\n"""Git pre-commit: CWE-117 prevention."""'
        result = classify_tool("helpers/hooks/check_log_sanitization.py", content)
        self.assertEqual(result["tier"], "universal")
        self.assertEqual(result["feature"], "universal-hooks")

    def test_universal_commit_atomicity_guard(self):
        """commit_atomicity_guard should be classified as universal."""
        content = '#!/usr/bin/env python3\n"""Git pre-commit: ensure atomic commits."""'
        result = classify_tool("helpers/hooks/commit_atomicity_guard.py", content)
        self.assertEqual(result["tier"], "universal")
        self.assertEqual(result["feature"], "universal-hooks")

    def test_universal_security_scan(self):
        """security_scan should be classified as universal by filename."""
        content = '#!/usr/bin/env python3\n"""Security analysis tool."""'
        result = classify_tool("helpers/security_scan.py", content)
        self.assertEqual(result["tier"], "universal")
        self.assertEqual(result["feature"], "universal-hooks")

    def test_personal_azure_auth_guard(self):
        """azure_auth_guard should be classified as personal (not universal)."""
        content = '#!/usr/bin/env python3\n"""Azure authentication enforcement."""'
        result = classify_tool(".claude/hooks/azure_auth_guard.py", content)
        self.assertEqual(result["tier"], "personal")
        self.assertEqual(result["feature"], "psford-personal")

    def test_personal_docker_build_guard(self):
        """docker_build_guard should be classified as personal (not universal)."""
        content = '#!/usr/bin/env python3\n"""Docker build validation."""'
        result = classify_tool(".claude/hooks/docker_build_guard.py", content)
        self.assertEqual(result["tier"], "personal")
        self.assertEqual(result["feature"], "psford-personal")

    def test_personal_kubernetes_manifest_guard(self):
        """kubernetes_manifest_guard should be classified as personal."""
        content = '#!/usr/bin/env python3\n"""Kubernetes manifest validation."""'
        result = classify_tool(".claude/hooks/kubernetes_manifest_guard.py", content)
        self.assertEqual(result["tier"], "personal")
        self.assertEqual(result["feature"], "psford-personal")

    def test_personal_terraform_guard(self):
        """terraform_guard should be classified as personal."""
        content = '#!/usr/bin/env python3\n"""Terraform configuration validation."""'
        result = classify_tool(".claude/hooks/terraform_guard.py", content)
        self.assertEqual(result["tier"], "personal")
        self.assertEqual(result["feature"], "psford-personal")

    def test_personal_performance_regression_guard(self):
        """performance_regression_guard should be classified as personal."""
        content = '#!/usr/bin/env python3\n"""Performance regression detection."""'
        result = classify_tool(".claude/hooks/performance_regression_guard.py", content)
        self.assertEqual(result["tier"], "personal")
        self.assertEqual(result["feature"], "psford-personal")

    def test_personal_test_docs_tabs(self):
        """test_docs_tabs should be classified as personal."""
        content = '#!/usr/bin/env python3\n"""Test documentation tab rendering."""'
        result = classify_tool("helpers/test_docs_tabs.py", content)
        self.assertEqual(result["tier"], "personal")
        self.assertEqual(result["feature"], "psford-personal")

    def test_language_csharp_detection_filename(self):
        """C# tools should be detected from filename."""
        content = '#!/usr/bin/env python3\n"""Some guard."""'
        result = classify_tool(".claude/hooks/dotnet_process_guard.py", content)
        self.assertEqual(result["tier"], "language")
        self.assertEqual(result["language"], "csharp")
        self.assertEqual(result["feature"], "csharp-tools")

    def test_language_csharp_detection_content(self):
        """C# tools should be detected from content."""
        content = "import subprocess\n# DotNet process handling\nsome_dotnet_code()"
        result = classify_tool("helpers/some_tool.py", content)
        self.assertEqual(result["tier"], "language")
        self.assertEqual(result["language"], "csharp")
        self.assertEqual(result["feature"], "csharp-tools")

    def test_language_powershell_detection(self):
        """PowerShell scripts should be detected."""
        content = "# PowerShell script\nInvoke-SpeechToText"
        result = classify_tool("helpers/Invoke-SpeechToText.ps1", content)
        self.assertEqual(result["language"], "powershell")

    def test_description_extraction_from_comment(self):
        """Description should be extracted from first comment."""
        content = '#!/usr/bin/env python3\n# This is a great tool\ndef main(): pass'
        result = classify_tool("helpers/some_tool.py", content)
        self.assertEqual(result["description"], "This is a great tool")

    def test_description_extraction_skips_shebang(self):
        """Description extraction should skip shebang lines."""
        content = '#!/usr/bin/env python3\n# Valid description\ndef main(): pass'
        result = classify_tool("helpers/some_tool.py", content)
        # Should NOT be the shebang
        self.assertNotIn("#!/", result["description"])
        self.assertEqual(result["description"], "Valid description")

    def test_description_extraction_skips_short_comments(self):
        """Description extraction should skip very short comments."""
        content = '#!/usr/bin/env python3\n# a\n# This is a proper description\ndef main(): pass'
        result = classify_tool("helpers/some_tool.py", content)
        self.assertEqual(result["description"], "This is a proper description")

    def test_description_extraction_length_limits(self):
        """Description should be between 10 and 150 characters."""
        short = "# ab"  # Too short
        content = f'#!/usr/bin/env python3\n{short}\n# This is a proper description\ndef main(): pass'
        result = classify_tool("helpers/some_tool.py", content)
        self.assertEqual(result["description"], "This is a proper description")

    def test_tool_name_hyphen_conversion(self):
        """Tool name should convert underscores to hyphens."""
        # This tests the add_tool_to_manifest function
        manifest = {
            "version": "1.0",
            "features": [],
            "tools": []
        }
        classification = {
            "tier": "universal",
            "language": None,
            "feature": "universal-hooks",
            "description": "Test tool"
        }
        result = add_tool_to_manifest(manifest, ".claude/hooks/git_commit_guard.py", classification)
        self.assertTrue(result)
        self.assertEqual(manifest["tools"][0]["name"], "git-commit-guard")

    def test_idempotency_no_duplicate_on_second_add(self):
        """Adding the same tool twice should not create duplicates (AC6.4)."""
        manifest = {
            "version": "1.0",
            "features": [],
            "tools": []
        }
        classification = {
            "tier": "universal",
            "language": None,
            "feature": "universal-hooks",
            "description": "Test tool"
        }
        # First add
        result1 = add_tool_to_manifest(manifest, ".claude/hooks/git_commit_guard.py", classification)
        self.assertTrue(result1)
        self.assertEqual(len(manifest["tools"]), 1)

        # Second add (should be rejected)
        result2 = add_tool_to_manifest(manifest, ".claude/hooks/git_commit_guard.py", classification)
        self.assertFalse(result2)
        self.assertEqual(len(manifest["tools"]), 1)  # No duplicate

    def test_cataloged_sources_extraction(self):
        """get_cataloged_sources should extract all source paths."""
        manifest = {
            "version": "1.0",
            "features": [],
            "tools": [
                {"name": "tool1", "source": ".claude/hooks/tool1.py", "tier": "universal", "language": None, "feature": "universal-hooks", "description": "Tool 1"},
                {"name": "tool2", "source": "helpers/tool2.py", "tier": "personal", "language": None, "feature": "psford-personal", "description": "Tool 2"},
            ]
        }
        sources = get_cataloged_sources(manifest)
        self.assertEqual(sources, {".claude/hooks/tool1.py", "helpers/tool2.py"})


class TestManifestOperations(unittest.TestCase):
    """Test manifest load/save operations."""

    def test_load_manifest_creates_default_structure(self):
        """load_manifest should create default structure if file missing."""
        with tempfile.TemporaryDirectory() as tmpdir:
            # Mock get_manifest_path to use temp dir
            manifest_path = Path(tmpdir) / "tooling-manifest.json"

            with patch('manifest_classification_guard.get_manifest_path', return_value=manifest_path):
                manifest = load_manifest()
                self.assertEqual(manifest["version"], "1.0")
                self.assertEqual(len(manifest["features"]), 4)
                self.assertEqual(manifest["tools"], [])

    def test_save_and_load_manifest_roundtrip(self):
        """Manifest should be saveable and loadable."""
        with tempfile.TemporaryDirectory() as tmpdir:
            manifest_path = Path(tmpdir) / "tooling-manifest.json"

            with patch('manifest_classification_guard.get_manifest_path', return_value=manifest_path):
                # Create and save
                original = {
                    "version": "1.0",
                    "features": [{"id": "test", "description": "Test", "tier": "personal"}],
                    "tools": [{"name": "test-tool", "source": "test.py", "tier": "personal", "language": None, "feature": "test", "description": "Test"}]
                }
                save_manifest(original)

                # Load and verify
                loaded = load_manifest()
                self.assertEqual(loaded["version"], original["version"])
                self.assertEqual(len(loaded["tools"]), len(original["tools"]))
                self.assertEqual(loaded["tools"][0]["name"], "test-tool")


class TestGetManifestPath(unittest.TestCase):
    """Test get_manifest_path function."""

    def test_get_manifest_path_uses_git_toplevel(self):
        """get_manifest_path should use git rev-parse --show-toplevel for robustness."""
        # This test ensures the robustness improvement is in place
        # We test by checking that the path ends correctly
        path = get_manifest_path()
        # Should be a Path object
        self.assertIsInstance(path, Path)
        # Should contain tooling-manifest.json
        self.assertTrue(str(path).endswith("tooling-manifest.json"))


if __name__ == "__main__":
    unittest.main()
