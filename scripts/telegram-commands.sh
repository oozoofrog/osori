#!/usr/bin/env bash
# Telegram bot command handler for osori
# Usage: telegram-commands.sh <command> [args...]

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REGISTRY_FILE="${OSORI_REGISTRY:-$HOME/.openclaw/osori.json}"

# Ensure registry exists + auto-migrate if needed
OSORI_SCRIPT_DIR="$SCRIPT_DIR" OSORI_REG="$REGISTRY_FILE" python3 << 'PYEOF' >/dev/null
import os
import sys
sys.path.insert(0, os.environ["OSORI_SCRIPT_DIR"])
from registry_lib import load_registry
load_registry(os.environ["OSORI_REG"], auto_migrate=True, make_backup_on_migrate=True)
PYEOF

show_help() {
    cat << 'EOF'
🦦 *Osori Bot Commands*

/list [root] — Show all projects (optionally filter by root)
/status [root] — Check project statuses (optionally filter by root)
/find <name> [root|--root <root>] — Find a project path (optional root scope)
/switch <name> [root|--root <root>] [--index <n>] — Switch to project & load context (multi-match selection)
/fingerprints [name] [--root <root>] — Show repo/commit/PR/issue fingerprints
/doctor [--fix] [--json] — Registry health check and safe auto-fix
/list-roots — List roots, labels, paths, project counts
/root-add <key> [label] — Add/update root
/root-path-add <key> <path> — Add discovery path to root
/root-path-remove <key> <path> — Remove discovery path from root
/root-set-label <key> <label> — Update root label
/root-remove <key> [--reassign <target>] [--force] — Safely remove root
/alias-add <alias> <project> — Add alias for project
/alias-remove <alias> — Remove alias
/favorites — Show favorite projects
/favorite-add <project> — Mark project as favorite
/favorite-remove <project> — Unmark favorite
/entire-status <project> [root|--root <root>] — Show Entire status in project
/entire-enable <project> [root|--root <root>] [--agent <name>] [--strategy <name>] — Enable Entire in project
/entire-rewind-list <project> [root|--root <root>] — List Entire rewind points (JSON)
/add <path> — Add project to registry
/remove <name> — Remove project from registry
/scan <path> [root] — Scan directory for projects (optional root key)
/help — Show this help

*Examples:*
`/list work`
`/status personal`
`/find agent-avengers work`
`/switch Tesella --root personal`
`/switch Tesella --root personal --index 1`
`/fingerprints Tesella --root personal`
`/doctor --fix`
`/list-roots`
`/root-add work Work`
`/root-path-add work /path/to/workspace`
`/root-remove work --reassign default`
`/alias-add rh RunnersHeart`
`/favorites`
`/entire-status osori`
`/entire-enable osori --agent claude-code --strategy manual-commit`
`/scan /path/to/workspace work`
EOF
}

cmd_list() {
    local root_filter="${1:-}"

    OSORI_ROOT_FILTER="$root_filter" OSORI_SCRIPT_DIR="$SCRIPT_DIR" OSORI_REG="$REGISTRY_FILE" python3 << 'PYSCRIPT'
import os
import sys

sys.path.insert(0, os.environ["OSORI_SCRIPT_DIR"])
from registry_lib import filter_projects, load_registry, registry_projects, registry_roots

root_filter = os.environ.get("OSORI_ROOT_FILTER", "").strip()

res = load_registry(os.environ["OSORI_REG"], auto_migrate=True, make_backup_on_migrate=True)
all_projects = registry_projects(res.registry)
projects = filter_projects(all_projects, root_key=root_filter)
roots = registry_roots(res.registry)
root_keys = [r.get('key', 'default') for r in roots]

if not projects:
    if root_filter:
        print(f"📂 No projects in root '{root_filter}'.")
        print(f"Available roots: {', '.join(root_keys)}")
    else:
        print("📂 No projects registered yet.")
    raise SystemExit(0)

header = f"📋 *{len(projects)} Projects*"
meta = f"(schema={res.registry.get('schema')} v{res.registry.get('version')})"
root_meta = f" [root={root_filter}]" if root_filter else ""
print(f"{header}{root_meta} {meta}\n")

for p in projects[:20]:
    name = p.get('name', '-')
    lang = p.get('lang', '-')
    root = p.get('root', 'default')
    tags = ', '.join(p.get('tags', [])) or '-'
    repo = p.get('repo', '')

    repo_str = f" | 🌐 {repo}" if repo else ""
    print(f"• *{name}* | {lang} | {root} | {tags}{repo_str}")

if len(projects) > 20:
    print(f"\n... and {len(projects) - 20} more")

if res.migrated:
    notes = '; '.join(res.migration_notes)
    print(f"\nℹ️ Migrated registry: {notes}")
    if res.backup_path:
        print(f"ℹ️ Migration backup: {res.backup_path}")
PYSCRIPT
}

cmd_status() {
    local root_filter="${1:-}"

    OSORI_ROOT_FILTER="$root_filter" OSORI_SCRIPT_DIR="$SCRIPT_DIR" OSORI_REG="$REGISTRY_FILE" python3 << 'PYSCRIPT'
import os
import subprocess
import sys

sys.path.insert(0, os.environ["OSORI_SCRIPT_DIR"])
from registry_lib import filter_projects, load_registry, registry_projects

root_filter = os.environ.get("OSORI_ROOT_FILTER", "").strip()

res = load_registry(os.environ["OSORI_REG"], auto_migrate=True, make_backup_on_migrate=True)
projects = filter_projects(registry_projects(res.registry), root_key=root_filter)

clean = modified = missing = 0

for p in projects:
    path = p.get('path', '')
    if not path or not os.path.exists(path):
        missing += 1
        continue

    try:
        result = subprocess.run(
            ['git', '-C', path, 'status', '--short'],
            capture_output=True, text=True, timeout=3,
        )
        if result.stdout.strip():
            modified += 1
        else:
            clean += 1
    except Exception:
        missing += 1

root_meta = f" [root={root_filter}]" if root_filter else ""
print(f"📊 *Project Status*{root_meta}\n")
print(f"✅ Clean: {clean}")
print(f"📝 Modified: {modified}")
print(f"⚠️ Missing: {missing}")
print(f"📁 Total: {len(projects)}")
print(f"🧾 Registry: schema={res.registry.get('schema')} v{res.registry.get('version')}")

if res.migrated:
    notes = '; '.join(res.migration_notes)
    print(f"\nℹ️ Migrated registry: {notes}")
    if res.backup_path:
        print(f"ℹ️ Migration backup: {res.backup_path}")
PYSCRIPT
}

cmd_find() {
    local name=""
    local root_filter=""

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --root)
                root_filter="${2:-}"
                shift 2
                ;;
            *)
                if [[ -z "$name" ]]; then
                    name="$1"
                elif [[ -z "$root_filter" ]]; then
                    root_filter="$1"
                fi
                shift
                ;;
        esac
    done

    [[ -z "$name" ]] && { echo "❌ Usage: /find <project-name> [root|--root <root>]"; exit 1; }

    OSORI_NAME="$name" OSORI_ROOT_FILTER="$root_filter" OSORI_SCRIPT_DIR="$SCRIPT_DIR" OSORI_REG="$REGISTRY_FILE" python3 << 'PYSCRIPT'
import os
import shutil
import subprocess
import sys

sys.path.insert(0, os.environ["OSORI_SCRIPT_DIR"])
from registry_lib import (
    filter_projects,
    load_registry,
    normalize_root_key,
    registry_projects,
    registry_roots,
    resolve_alias,
    search_paths_for_discovery,
)


def within_any(path, roots):
    rp = os.path.realpath(path)
    for root in roots:
        rr = os.path.realpath(root)
        try:
            if os.path.commonpath([rp, rr]) == rr:
                return True
        except Exception:
            continue
    return False


name = os.environ["OSORI_NAME"].strip()
root_filter = os.environ.get("OSORI_ROOT_FILTER", "").strip()

res = load_registry(os.environ["OSORI_REG"], auto_migrate=True, make_backup_on_migrate=True)
resolved_name = resolve_alias(name, res.registry)
query = resolved_name.lower()
projects = filter_projects(registry_projects(res.registry), root_key=root_filter)
root_key = normalize_root_key(root_filter)
roots_meta = registry_roots(res.registry)
root_keys = [r.get("key", "default") for r in roots_meta]

if resolved_name != name:
    print(f"ℹ️ alias resolved: {name} -> {resolved_name}")

# 1) Registry lookup (root-prioritized when root_filter is set)
for p in projects:
    pname = p.get('name', '')
    if query in pname.lower():
        print(f"📁 *{pname}*")
        print(f"📍 {p.get('path', '-')}")
        if p.get('repo'):
            print(f"🌐 {p.get('repo')}")
        if p.get('lang') and p.get('lang') != 'unknown':
            print(f"🔤 {p.get('lang')}")
        print(f"🧭 root: {p.get('root', 'default')}")
        if res.migrated:
            notes = '; '.join(res.migration_notes)
            print(f"\nℹ️ Migrated registry: {notes}")
            if res.backup_path:
                print(f"ℹ️ Migration backup: {res.backup_path}")
        raise SystemExit(0)

# Build prioritized search paths from roots[].paths + OSORI_SEARCH_PATHS
search_paths = search_paths_for_discovery(
    res.registry,
    root_key=root_filter,
    env_paths=os.environ.get('OSORI_SEARCH_PATHS', ''),
)

# 2) Spotlight (macOS)
if shutil.which('mdfind'):
    r = subprocess.run(['mdfind', f'kMDItemFSName == "{resolved_name}"'], capture_output=True, text=True)
    lines = [line for line in r.stdout.strip().split('\n') if line.strip()]
    if lines:
        if root_key:
            root_only_paths = search_paths_for_discovery(res.registry, root_key=root_filter, env_paths='')
            if root_only_paths:
                lines = [line for line in lines if within_any(line, root_only_paths)]
        if lines:
            print("🔍 *Found via Spotlight:*")
            for p in lines[:3]:
                print(f"📍 {p}")
            raise SystemExit(0)

# 3) find fallback (root paths first)
for sp in search_paths:
    if not os.path.exists(sp):
        continue
    r = subprocess.run(
        ['find', sp, '-maxdepth', '4', '-type', 'd', '-name', f'*{name}*'],
        capture_output=True, text=True, timeout=10,
    )
    lines = [line for line in r.stdout.strip().split('\n') if line.strip()]
    if lines:
        print("🔍 *Found via search:*")
        for p in lines[:3]:
            print(f"📍 {p}")
        raise SystemExit(0)

if root_key and root_key not in root_keys:
    print(f"ℹ️ Unknown root '{root_key}'. Available roots: {', '.join(root_keys)}")

if not search_paths:
    print("ℹ️ Tip: set roots[].paths in registry or OSORI_SEARCH_PATHS for fallback discovery")

print(f"❌ Project '{name}' not found.")
PYSCRIPT
}

cmd_switch() {
    local name=""
    local root_filter=""
    local index_arg=""

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --root)
                root_filter="${2:-}"
                shift 2
                ;;
            --index)
                index_arg="${2:-}"
                shift 2
                ;;
            *)
                if [[ -z "$name" ]]; then
                    name="$1"
                elif [[ -z "$root_filter" ]]; then
                    root_filter="$1"
                fi
                shift
                ;;
        esac
    done

    [[ -z "$name" ]] && { echo "❌ Usage: /switch <project-name> [root|--root <root>] [--index <n>]"; exit 1; }

    OSORI_NAME="$name" OSORI_ROOT_FILTER="$root_filter" OSORI_SWITCH_INDEX="$index_arg" OSORI_SCRIPT_DIR="$SCRIPT_DIR" OSORI_REG="$REGISTRY_FILE" python3 << 'PYSCRIPT'
import json
import os
import shutil
import subprocess
import sys

sys.path.insert(0, os.environ["OSORI_SCRIPT_DIR"])
from github_cache import DEFAULT_CACHE_PATH, get_open_count
from registry_lib import (
    filter_projects,
    load_registry,
    normalize_root_key,
    parse_repo_from_remote,
    registry_projects,
    registry_roots,
    resolve_alias,
    search_paths_for_discovery,
)


def run(cmd, timeout=8):
    try:
        p = subprocess.run(cmd, capture_output=True, text=True, timeout=timeout)
        return p.returncode, p.stdout.strip(), p.stderr.strip()
    except Exception as e:
        return 1, "", str(e)


try:
    CACHE_TTL = int(os.environ.get("OSORI_CACHE_TTL", "600"))
except Exception:
    CACHE_TTL = 600
CACHE_PATH = os.environ.get("OSORI_CACHE_FILE", DEFAULT_CACHE_PATH)


def gh_count(kind, repo):
    if not repo or shutil.which("gh") is None:
        return "n/a"

    def fetch():
        rc, out, _ = run(["gh", kind, "list", "-R", repo, "--state", "open", "--json", "number", "--limit", "200"], timeout=12)
        if rc != 0 or not out:
            return None
        try:
            return len(json.loads(out))
        except Exception:
            return None

    value, _state = get_open_count(
        kind=kind,
        repo=repo,
        ttl_seconds=CACHE_TTL,
        cache_path=CACHE_PATH,
        fetch_open_count=fetch,
    )
    return value


def git_last_commit(path):
    rc_iso, iso, _ = run(["git", "-C", path, "log", "-1", "--format=%cI"])
    rc_ts, ts, _ = run(["git", "-C", path, "log", "-1", "--format=%ct"])
    if rc_iso != 0 or not iso:
        iso = "n/a"
    if rc_ts != 0 or not ts:
        return iso, 0
    try:
        return iso, int(ts)
    except Exception:
        return iso, 0


def git_dirty(path):
    rc, out, _ = run(["git", "-C", path, "status", "--short"])
    if rc != 0:
        return "n/a"
    return "dirty" if bool(out.strip()) else "clean"


name_raw = os.environ["OSORI_NAME"].strip()
root_filter = os.environ.get("OSORI_ROOT_FILTER", "").strip()
index_arg = os.environ.get("OSORI_SWITCH_INDEX", "").strip()
root_key = normalize_root_key(root_filter)

res = load_registry(os.environ["OSORI_REG"], auto_migrate=True, make_backup_on_migrate=True)
resolved_name = resolve_alias(name_raw, res.registry)
name = resolved_name.lower()
projects = filter_projects(registry_projects(res.registry), root_key=root_filter)
roots = [r.get("key", "default") for r in registry_roots(res.registry)]

if resolved_name != name_raw:
    print(f"ℹ️ alias resolved: {name_raw} -> {resolved_name}")

candidates = []
for p in projects:
    pname = str(p.get("name", ""))
    if name not in pname.lower():
        continue

    ppath = str(p.get("path", ""))
    exists = bool(ppath) and os.path.exists(ppath)
    commit_iso = "n/a"
    commit_ts = 0
    dirty = "n/a"

    if exists:
        commit_iso, commit_ts = git_last_commit(ppath)
        dirty = git_dirty(ppath)

    candidates.append({
        "project": p,
        "name": pname,
        "root": str(p.get("root", "default") or "default"),
        "path": ppath,
        "exists": exists,
        "repo": str(p.get("repo", "") or ""),
        "commit_iso": commit_iso,
        "commit_ts": commit_ts,
        "dirty": dirty,
        "score": 0,
    })

if not candidates:
    if root_key:
        print(f"❌ Project '{name_raw}' not found in root '{root_key}' registry.")
    else:
        print(f"❌ Project '{name_raw}' not found in registry.")

    if root_key and root_key not in roots:
        print(f"ℹ️ Available roots: {', '.join(roots)}")

    # Suggest possible paths using prioritized discovery paths
    search_paths = search_paths_for_discovery(res.registry, root_key=root_filter, env_paths=os.environ.get('OSORI_SEARCH_PATHS', ''))
    hints = []
    for sp in search_paths:
        if not os.path.exists(sp):
            continue
        rc, out, _ = run(['find', sp, '-maxdepth', '4', '-type', 'd', '-name', f'*{name_raw}*'], timeout=10)
        if rc != 0 or not out:
            continue
        for line in out.split('\n'):
            line = line.strip()
            if line:
                hints.append(line)
            if len(hints) >= 3:
                break
        if hints:
            break

    if hints:
        print("\n🔍 Possible paths:")
        for h in hints:
            print(f"  - {h}")
        print("\nUse /add <path> then /switch again.")

    raise SystemExit(1)

# Score policy (roadmap fixed)
max_commit_ts = max((c["commit_ts"] for c in candidates), default=0)
for c in candidates:
    score = 0
    nlow = c["name"].lower()

    if root_key and c["root"] == root_key:
        score += 50
    if nlow == name:
        score += 30
    if nlow.startswith(name):
        score += 20
    if max_commit_ts > 0 and c["commit_ts"] == max_commit_ts:
        score += 10
    if not c["exists"]:
        score -= 10
    if not c["repo"]:
        score -= 5

    c["score"] = score

candidates.sort(key=lambda c: (-c["score"], -c["commit_ts"], c["name"].lower()))

if len(candidates) > 1:
    print(f"🔎 Multiple matches ({len(candidates)}):")
    for idx, c in enumerate(candidates, 1):
        print(
            f"  {idx}. {c['name']} [{c['root']}] | score={c['score']} | "
            f"dirty={c['dirty']} | last={c['commit_iso']}"
        )
    print()

selected = None
if index_arg:
    try:
        index_val = int(index_arg)
    except Exception:
        print(f"❌ invalid --index value: {index_arg!r}")
        raise SystemExit(1)

    if index_val < 1 or index_val > len(candidates):
        print(f"❌ --index out of range: {index_val} (1..{len(candidates)})")
        raise SystemExit(1)

    selected = candidates[index_val - 1]
    if len(candidates) > 1:
        print(f"✅ Selected candidate #{index_val} explicitly.\n")
else:
    selected = candidates[0]
    if len(candidates) > 1:
        print("🤖 Auto-selected #1 by score policy. Use --index <n> to choose explicitly.\n")

target = selected["project"]
path = selected["path"]
if not path or not os.path.exists(path):
    print(f"⚠️ Path does not exist: {path}")
    raise SystemExit(1)

print(f"📁 *{target.get('name')}*")
print(f"📍 {path}")
print(f"🧭 root: {target.get('root', 'default')}")

# git status
_, status_out, _ = run(['git', '-C', path, 'status', '--short'])
if status_out:
    print("\n📝 Changes:")
    for line in status_out.split('\n')[:5]:
        print(f"  {line}")
else:
    print("\n✅ Clean working tree")

# branch
_, branch, _ = run(['git', '-C', path, 'branch', '--show-current'])
print(f"\n🌿 Branch: {branch or '-'}")

# recent commits
_, log, _ = run(['git', '-C', path, 'log', '--oneline', '-3'])
if log:
    print("\n💬 Recent commits:")
    for line in log.split('\n'):
        print(f"  {line}")

# fingerprints
_, remote, _ = run(['git', '-C', path, 'remote', 'get-url', 'origin'])
repo = target.get('repo', '') or parse_repo_from_remote(remote)
_, last, _ = run(['git', '-C', path, 'log', '-1', '--format=%H|%cI'])
if '|' in last:
    commit_hash, commit_date = last.split('|', 1)
    last_commit = f"{commit_hash} ({commit_date})"
else:
    last_commit = 'n/a'

print("\n🧬 Fingerprint:")
print(f"  - remote: {remote or 'n/a'}")
print(f"  - last commit: {last_commit}")
print(f"  - open PRs: {gh_count('pr', repo)}")
print(f"  - open issues: {gh_count('issue', repo)}")

if res.migrated:
    notes = '; '.join(res.migration_notes)
    print(f"\nℹ️ Migrated registry: {notes}")
    if res.backup_path:
        print(f"ℹ️ Migration backup: {res.backup_path}")
PYSCRIPT
}

cmd_fingerprints() {
    bash "$SCRIPT_DIR/project-fingerprints.sh" "$@"
}

cmd_add() {
    local path="${1:-}"
    [[ -z "$path" ]] && { echo "❌ Usage: /add <path>"; exit 1; }
    [[ ! -d "$path" ]] && { echo "❌ Directory not found: $path"; exit 1; }

    bash "$SCRIPT_DIR/add-project.sh" "$path"
}

cmd_remove() {
    local name="${1:-}"
    [[ -z "$name" ]] && { echo "❌ Usage: /remove <project-name>"; exit 1; }

    OSORI_NAME="$name" OSORI_SCRIPT_DIR="$SCRIPT_DIR" OSORI_REG="$REGISTRY_FILE" python3 << 'PYSCRIPT'
import os
import sys

sys.path.insert(0, os.environ["OSORI_SCRIPT_DIR"])
from registry_lib import load_registry, registry_projects, save_registry, set_registry_projects

name = os.environ["OSORI_NAME"]
res = load_registry(os.environ["OSORI_REG"], auto_migrate=True, make_backup_on_migrate=True)
registry = res.registry
projects = registry_projects(registry)

original_len = len(projects)
projects = [p for p in projects if p.get('name', '').lower() != name.lower()]

if len(projects) == original_len:
    print(f"❌ Project '{name}' not found.")
    raise SystemExit(1)

set_registry_projects(registry, projects)
backup_path = save_registry(os.environ["OSORI_REG"], registry, make_backup=True)

print(f"✅ Removed: {name}")
if backup_path:
    print(f"Backup: {backup_path}")
PYSCRIPT
}

cmd_scan() {
    local path="${1:-}"
    local root_key="${2:-}"

    local default_scan_root="${OSORI_SCAN_DEFAULT:-${OSORI_SEARCH_PATHS%%:*}}"
    if [[ -z "$path" ]]; then
      path="${default_scan_root:-.}"
    fi

    [[ ! -d "$path" ]] && { echo "❌ Directory not found: $path"; exit 1; }

    if [[ -n "$root_key" ]]; then
      echo "🔍 *Scanning for git repositories...* (root=$root_key)"
      OSORI_ROOT_KEY="$root_key" bash "$SCRIPT_DIR/scan-projects.sh" "$path" --depth 2
    else
      echo "🔍 *Scanning for git repositories...*"
      bash "$SCRIPT_DIR/scan-projects.sh" "$path" --depth 2
    fi
}

cmd_doctor() {
    bash "$SCRIPT_DIR/doctor.sh" "$@"
}

cmd_list_roots() {
    bash "$SCRIPT_DIR/root-manager.sh" list
}

cmd_root_add() {
    local key="${1:-}"
    shift || true
    local label="${*:-}"

    [[ -z "$key" ]] && { echo "❌ Usage: /root-add <key> [label]"; exit 1; }

    if [[ -n "$label" ]]; then
      bash "$SCRIPT_DIR/root-manager.sh" add "$key" "$label"
    else
      bash "$SCRIPT_DIR/root-manager.sh" add "$key"
    fi
}

cmd_root_path_add() {
    local key="${1:-}"
    local path="${2:-}"
    [[ -z "$key" || -z "$path" ]] && { echo "❌ Usage: /root-path-add <key> <path>"; exit 1; }
    bash "$SCRIPT_DIR/root-manager.sh" path-add "$key" "$path"
}

cmd_root_path_remove() {
    local key="${1:-}"
    local path="${2:-}"
    [[ -z "$key" || -z "$path" ]] && { echo "❌ Usage: /root-path-remove <key> <path>"; exit 1; }
    bash "$SCRIPT_DIR/root-manager.sh" path-remove "$key" "$path"
}

cmd_root_set_label() {
    local key="${1:-}"
    shift || true
    local label="${*:-}"

    [[ -z "$key" || -z "$label" ]] && { echo "❌ Usage: /root-set-label <key> <label>"; exit 1; }
    bash "$SCRIPT_DIR/root-manager.sh" set-label "$key" "$label"
}

cmd_root_remove() {
    local key="${1:-}"
    shift || true

    [[ -z "$key" ]] && { echo "❌ Usage: /root-remove <key> [--reassign <target>] [--force]"; exit 1; }

    bash "$SCRIPT_DIR/root-manager.sh" remove "$key" "$@"
}

cmd_alias_add() {
    local alias_key="${1:-}"
    local project="${2:-}"
    [[ -z "$alias_key" || -z "$project" ]] && { echo "❌ Usage: /alias-add <alias> <project>"; exit 1; }
    bash "$SCRIPT_DIR/alias-favorite-manager.sh" alias-add "$alias_key" "$project"
}

cmd_alias_remove() {
    local alias_key="${1:-}"
    [[ -z "$alias_key" ]] && { echo "❌ Usage: /alias-remove <alias>"; exit 1; }
    bash "$SCRIPT_DIR/alias-favorite-manager.sh" alias-remove "$alias_key"
}

cmd_favorites() {
    bash "$SCRIPT_DIR/alias-favorite-manager.sh" favorites
}

cmd_favorite_add() {
    local project="${1:-}"
    [[ -z "$project" ]] && { echo "❌ Usage: /favorite-add <project>"; exit 1; }
    bash "$SCRIPT_DIR/alias-favorite-manager.sh" favorite-add "$project"
}

cmd_favorite_remove() {
    local project="${1:-}"
    [[ -z "$project" ]] && { echo "❌ Usage: /favorite-remove <project>"; exit 1; }
    bash "$SCRIPT_DIR/alias-favorite-manager.sh" favorite-remove "$project"
}

cmd_entire_status() {
    [[ $# -lt 1 ]] && { echo "❌ Usage: /entire-status <project> [root|--root <root>]"; exit 1; }
    bash "$SCRIPT_DIR/entire-manager.sh" status "$@"
}

cmd_entire_enable() {
    [[ $# -lt 1 ]] && { echo "❌ Usage: /entire-enable <project> [root|--root <root>] [--agent <name>] [--strategy <name>]"; exit 1; }
    bash "$SCRIPT_DIR/entire-manager.sh" enable "$@"
}

cmd_entire_rewind_list() {
    [[ $# -lt 1 ]] && { echo "❌ Usage: /entire-rewind-list <project> [root|--root <root>]"; exit 1; }
    bash "$SCRIPT_DIR/entire-manager.sh" rewind-list "$@"
}

# Main dispatch
command="${1:-help}"
if [[ $# -gt 0 ]]; then
  shift
fi

case "$command" in
    list) cmd_list "${1:-}" ;;
    status) cmd_status "${1:-}" ;;
    find) cmd_find "$@" ;;
    switch) cmd_switch "$@" ;;
    fingerprints) cmd_fingerprints "$@" ;;
    doctor) cmd_doctor "$@" ;;
    list-roots|roots) cmd_list_roots ;;
    root-add) cmd_root_add "$@" ;;
    root-path-add) cmd_root_path_add "$@" ;;
    root-path-remove) cmd_root_path_remove "$@" ;;
    root-set-label) cmd_root_set_label "$@" ;;
    root-remove) cmd_root_remove "$@" ;;
    alias-add) cmd_alias_add "${1:-}" "${2:-}" ;;
    alias-remove) cmd_alias_remove "${1:-}" ;;
    favorites) cmd_favorites ;;
    favorite-add) cmd_favorite_add "${1:-}" ;;
    favorite-remove) cmd_favorite_remove "${1:-}" ;;
    entire-status) cmd_entire_status "$@" ;;
    entire-enable) cmd_entire_enable "$@" ;;
    entire-rewind-list) cmd_entire_rewind_list "$@" ;;
    add) cmd_add "${1:-}" ;;
    remove) cmd_remove "${1:-}" ;;
    scan) cmd_scan "${1:-}" "${2:-}" ;;
    help|--help|-h) show_help ;;
    *) echo "❌ Unknown command: $command"; show_help; exit 1 ;;
esac