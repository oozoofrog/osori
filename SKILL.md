---
name: osori
description: "Osori v1.4.0 — Local project registry & context loader with Telegram slash commands. Registry versioning + auto-migration + fingerprints view + root filters + root management commands. Find, switch, list, add/remove projects, check status. Triggers: work on X, find project X, list projects, project status, project switch. | 오소리 — 텔레그램 슬래시 명령어 지원 로컬 프로젝트 레지스트리."
---

# Osori (오소리)

Local project registry & context loader for AI agents.

## Prerequisites

- **macOS**: `mdfind` (Spotlight, built-in), `python3`, `git`, `gh` CLI
- **Linux**: `mdfind` unavailable → uses `find` as fallback automatically. `python3`, `git`, `gh` CLI required.

## Dependencies

- **python3** — Required. Used for JSON processing.
- **git** — Project detection and status checks.

## Telegram Bot Commands (Updated in v1.4.0)

Osori now supports Telegram slash commands for quick project management:

```
/list [root] — Show registered projects (optional root filter)
/status [root] — Check status of projects (optional root filter)
/find <name> [root|--root <root>] — Find a project by name (optional root scope)
/switch <name> [root|--root <root>] — Switch to project and load context (optional root scope)
/fingerprints [name] [--root <root>] — Show repo remote + last commit + open PR/issue counts
/list-roots — List roots, labels, paths, and project counts
/root-add <key> [label] — Add root (or update label)
/root-path-add <key> <path> — Add discovery path to root
/root-path-remove <key> <path> — Remove discovery path from root
/root-set-label <key> <label> — Update root label
/add <path> — Add project to registry
/remove <name> — Remove project from registry
/scan <path> [root] — Scan directory for git projects, optional root key
/help — Show command help
```

### Setup

Add to your OpenClaw agent's TOOLS.md or Telegram bot config:

```bash
# In Telegram bot commands (BotFather)
list - Show all projects (or by root)
status - Check project statuses (or by root)
find - Find project by name
switch - Switch to project
fingerprints - Show repo/commit/PR/issue fingerprint
list-roots - Show roots and discovery paths
root-add - Add root
root-path-add - Add path to root
root-path-remove - Remove path from root
root-set-label - Rename root label
add - Add project to registry
remove - Remove project
scan - Scan directory (optional root)
help - Show help
```

### Usage Examples

```
/list work
/status personal
/find agent-avengers work
/switch Tesella --root personal
/fingerprints Tesella --root personal
/list-roots
/root-add work Work
/root-path-add work /path/to/workspace
/add /Volumes/disk/MyProject
/scan /path/to/workspace work
```

## Registry

`${OSORI_REGISTRY:-$HOME/.openclaw/osori.json}`

Override with the `OSORI_REGISTRY` environment variable.

### Versioning & Migration (v1.4.0)

- Current schema: `osori.registry`
- Current version: `2`
- On every load, Osori auto-migrates older registry formats:
  - legacy array (`[]`) → versioned object
  - object without `schema/version` → normalized versioned object
- Migration safety:
  - creates backup: `osori.json.bak-<timestamp>`
  - corrupted JSON is preserved as: `osori.json.broken-<timestamp>`
  - write path uses atomic replace + rollback fallback

## Finding Projects (when path is unknown)

When the project path is unknown, search in order:

1. **Registry lookup** — Fuzzy match name in `osori.json`
2. **mdfind** (macOS only) — `mdfind "kMDItemFSName == '<name>'" | head -5`
3. **find fallback** — Search priority:
   1) `roots[].paths` from registry (if root is specified, that root first)
   2) paths from `OSORI_SEARCH_PATHS`
   Command form: `find <search_paths> -maxdepth 4 -type d -name '<name>' 2>/dev/null`
4. **Ask the user** — If all methods fail, ask for the project path directly.
5. Offer to register the found project in the registry.

## Commands

### List
Show all registered projects. Optional root filter supported in Telegram command:

```bash
/list [root]
```

(Example: `/list work`)

### Switch
Supports optional root scope:

```bash
/switch <name> [root|--root <root>]
```

Flow:
1. Search registry (fuzzy match, root-prioritized if provided)
2. If not found → run "Finding Projects" flow above and suggest add path
3. Load context:
   - `git status --short`
   - `git branch --show-current`
   - `git log --oneline -5`
   - `gh issue list -R <repo> --limit 5` (when repo is set)
4. Present summary

### Fingerprints
Show a one-shot project fingerprint view:
- repo remote URL
- last commit hash/date
- open PR count
- open issue count

```bash
bash skills/osori/scripts/project-fingerprints.sh [project-name]
bash skills/osori/scripts/project-fingerprints.sh --root <root-key> [project-name]
```

### Add
```bash
bash skills/osori/scripts/add-project.sh <path> [--tag <tag>] [--name <name>]
```
Auto-detects: git remote, language, description.

### Scan
```bash
bash skills/osori/scripts/scan-projects.sh <root-dir> [--depth 3]
OSORI_ROOT_KEY=work bash skills/osori/scripts/scan-projects.sh <root-dir> [--depth 3]
```
Bulk-scan a directory for git repos and add them to the registry.

Telegram command supports optional root key too:

```bash
/scan <path> [root]
```

### Remove
Delete an entry from `osori.json` by name.

### Status
Run `git status` + `gh issue list` for one or all projects.

Telegram root filter:

```bash
/status [root]
```

### Root Management

```bash
/list-roots
/root-add <key> [label]
/root-path-add <key> <path>
/root-path-remove <key> <path>
/root-set-label <key> <label>
```

Shell equivalents:

```bash
bash skills/osori/scripts/root-manager.sh list
bash skills/osori/scripts/root-manager.sh add <key> [label]
bash skills/osori/scripts/root-manager.sh path-add <key> <path>
bash skills/osori/scripts/root-manager.sh path-remove <key> <path>
bash skills/osori/scripts/root-manager.sh set-label <key> <label>
```

## Schema

```json
{
  "schema": "osori.registry",
  "version": 2,
  "updatedAt": "2026-02-16T00:00:00Z",
  "roots": [
    {
      "key": "default",
      "label": "Default",
      "paths": []
    }
  ],
  "projects": [
    {
      "name": "string",
      "path": "/absolute/path",
      "repo": "owner/repo",
      "lang": "swift|typescript|python|rust|go|ruby|unknown",
      "tags": ["personal", "ios"],
      "description": "Short description",
      "addedAt": "YYYY-MM-DD",
      "root": "default"
    }
  ]
}
```

## Auto-trigger Rules

- "work on X" / "X 프로젝트 작업하자" → switch X
- "find project X" / "X 찾아줘" / "X 경로" → registry search or discover
- "list projects" / "프로젝트 목록" → list
- "add project" / "프로젝트 추가" → add
- "project status" / "프로젝트 상태" → status all
