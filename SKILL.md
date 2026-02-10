---
name: osori
description: "Osori v1.2.0 — Local project registry & context loader with Telegram slash commands. Find, switch, list, add/remove projects, check status. Triggers: work on X, find project X, list projects, project status, project switch. | 오소리 — 텔레그램 슬래시 명령어 지원 로컬 프로젝트 레지스트리."
---

# Osori (오소리)

Local project registry & context loader for AI agents.

## Prerequisites

- **macOS**: `mdfind` (Spotlight, built-in), `python3`, `git`, `gh` CLI
- **Linux**: `mdfind` unavailable → uses `find` as fallback automatically. `python3`, `git`, `gh` CLI required.

## Dependencies

- **python3** — Required. Used for JSON processing.
- **git** — Project detection and status checks.

## Telegram Bot Commands (New in v1.2.0)

Osori now supports Telegram slash commands for quick project management:

```
/list — Show all registered projects
/status — Check status of all projects
/find <name> — Find a project by name
/switch <name> — Switch to project and load context
/add <path> — Add project to registry
/remove <name> — Remove project from registry
/scan <path> — Scan directory for git projects
/help — Show command help
```

### Setup

Add to your OpenClaw agent's TOOLS.md or Telegram bot config:

```bash
# In Telegram bot commands (BotFather)
list - Show all projects
status - Check project statuses
find - Find project by name
switch - Switch to project
add - Add project to registry
remove - Remove project
scan - Scan directory
help - Show help
```

### Usage Examples

```
/find agent-avengers
/switch Tesella
/add /Volumes/disk/MyProject
/scan /Volumes/eyedisk/develop
```

## Registry

`${OSORI_REGISTRY:-$HOME/.openclaw/osori.json}`

Override with the `OSORI_REGISTRY` environment variable.

## Finding Projects (when path is unknown)

When the project path is unknown, search in order:

1. **Registry lookup** — Fuzzy match name in `osori.json`
2. **mdfind** (macOS only) — `mdfind "kMDItemFSName == '<name>'" | head -5`
3. **find fallback** — Search paths defined in `OSORI_SEARCH_PATHS` env var. If unset, ask the user for search paths.
   `find <search_paths> -maxdepth 4 -type d -name '<name>' 2>/dev/null`
4. **Ask the user** — If all methods fail, ask for the project path directly.
5. Offer to register the found project in the registry.

## Commands

### List
Show all registered projects. Supports `--tag`, `--lang` filters.
```
Read osori.json and display as a table.
```

### Switch
1. Search registry (fuzzy match)
2. If not found → run "Finding Projects" flow above
3. Load context:
   - `git status --short`
   - `git branch --show-current`
   - `git log --oneline -5`
   - `gh issue list -R <repo> --limit 5` (when repo is set)
4. Present summary

### Add
```bash
bash skills/osori/scripts/add-project.sh <path> [--tag <tag>] [--name <name>]
```
Auto-detects: git remote, language, description.

### Scan
```bash
bash skills/osori/scripts/scan-projects.sh <root-dir> [--depth 3]
```
Bulk-scan a directory for git repos and add them to the registry.

### Remove
Delete an entry from `osori.json` by name.

### Status
Run `git status` + `gh issue list` for one or all projects.

## Schema

```json
{
  "name": "string",
  "path": "/absolute/path",
  "repo": "owner/repo",
  "lang": "swift|typescript|python|rust|go|ruby|unknown",
  "tags": ["personal", "ios"],
  "description": "Short description",
  "addedAt": "YYYY-MM-DD"
}
```

## Auto-trigger Rules

- "work on X" / "X 프로젝트 작업하자" → switch X
- "find project X" / "X 찾아줘" / "X 경로" → registry search or discover
- "list projects" / "프로젝트 목록" → list
- "add project" / "프로젝트 추가" → add
- "project status" / "프로젝트 상태" → status all
