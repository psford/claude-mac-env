# Tooling Manifest Schema

The `tooling-manifest.json` file in the `claude-env` repository catalogs all Claude Code hooks and helper scripts with metadata for tiered installation.

## Structure

The manifest is a JSON object with three top-level fields:

### `version` (string)

Schema version for forward compatibility. Current version: `"1.0"`.

### `features` (array of objects)

Defines available Features that tools can belong to. Each Feature has:

- `id` (string): Feature identifier (e.g., `"universal-hooks"`)
- `description` (string): Human-readable Feature description
- `tier` (enum): Availability level: `"always"`, `"universal"`, `"language"`, or `"personal"`

Features are:
- **always**: `claude-skills` — installed for all users
- **universal**: `universal-hooks` — broadly applicable hooks for everyone
- **language**: `csharp-tools` — language-specific tooling
- **personal**: `psford-personal` — personal/project-specific utilities

### `tools` (array of objects)

Catalog of all hooks and helpers. Each tool entry has:

- `name` (string): Unique tool identifier
- `source` (string): File path relative to `claude-env` root (e.g., `.claude/hooks/git_commit_guard.py`)
- `tier` (enum): `"universal"`, `"language"`, or `"personal"`
- `language` (string | null): Language affinity (`null` for universal tools, e.g., `"csharp"`, `"python"`)
- `feature` (string): Target Feature ID this tool belongs to
- `description` (string): One-line description displayed during setup

## Example

```json
{
  "version": "1.0",
  "features": [
    {
      "id": "universal-hooks",
      "description": "Git hooks for branch protection and commit validation",
      "tier": "universal"
    },
    {
      "id": "csharp-tools",
      "description": ".NET SDK and C# development helpers",
      "tier": "language"
    }
  ],
  "tools": [
    {
      "name": "git-commit-guard",
      "source": ".claude/hooks/git_commit_guard.py",
      "tier": "universal",
      "language": null,
      "feature": "universal-hooks",
      "description": "Validates git commit standards before pushing"
    },
    {
      "name": "dotnet-process-guard",
      "source": ".claude/hooks/dotnet_process_guard.py",
      "tier": "language",
      "language": "csharp",
      "feature": "csharp-tools",
      "description": ".NET process monitoring and enforcement"
    }
  ]
}
```

## Usage in setup.sh

The manifest drives tiered tooling selection:

1. For `psford` user: all Features installed without prompts
2. For other users: manifest tools displayed by tier/language with descriptions
3. Already-cataloged files not shown again (no duplicates)

## Validation

The manifest must validate against the JSON Schema in `tooling-manifest.schema.json` in the same repository.

Validate with:
```bash
python3 -c "import json; json.load(open('tooling-manifest.json')); print('Valid')"
```

## Maintenance

The manifest is automatically updated by the commit hook `manifest_classification_guard.py` when new tool files are staged, reducing manual maintenance burden. The hook classifies new tools by content analysis and proposes entries for author review.
