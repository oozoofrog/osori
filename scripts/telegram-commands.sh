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

/list — Show all projects
/status — Check all project statuses
/find <name> — Find a project path
/switch <name> — Switch to project & load context
/fingerprints [name] — Show repo/commit/PR/issue fingerprints
/add <path> — Add project to registry
/remove <name> — Remove project from registry
/scan <path> — Scan directory for projects
/help — Show this help

*Examples:*
`/find agent-avengers`
`/switch Tesella`
`/fingerprints Tesella`
`/add /Volumes/disk/MyProject`
EOF
}

cmd_list() {
    OSORI_SCRIPT_DIR="$SCRIPT_DIR" OSORI_REG="$REGISTRY_FILE" python3 << 'PYSCRIPT'
import os
import sys

sys.path.insert(0, os.environ["OSORI_SCRIPT_DIR"])
from registry_lib import load_registry, registry_projects

res = load_registry(os.environ["OSORI_REG"], auto_migrate=True, make_backup_on_migrate=True)
projects = registry_projects(res.registry)

if not projects:
    print("📂 No projects registered yet.")
    raise SystemExit(0)

header = f"📋 *{len(projects)} Projects*"
meta = f"(schema={res.registry.get('schema')} v{res.registry.get('version')})"
print(f"{header} {meta}\n")

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
    OSORI_SCRIPT_DIR="$SCRIPT_DIR" OSORI_REG="$REGISTRY_FILE" python3 << 'PYSCRIPT'
import os
import subprocess
import sys

sys.path.insert(0, os.environ["OSORI_SCRIPT_DIR"])
from registry_lib import load_registry, registry_projects

res = load_registry(os.environ["OSORI_REG"], auto_migrate=True, make_backup_on_migrate=True)
projects = registry_projects(res.registry)

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

print("📊 *Project Status*\n")
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
    local name="${1:-}"
    [[ -z "$name" ]] && { echo "❌ Usage: /find <project-name>"; exit 1; }

    OSORI_NAME="$name" OSORI_SCRIPT_DIR="$SCRIPT_DIR" OSORI_REG="$REGISTRY_FILE" python3 << 'PYSCRIPT'
import os
import shutil
import subprocess
import sys

sys.path.insert(0, os.environ["OSORI_SCRIPT_DIR"])
from registry_lib import load_registry, registry_projects

name = os.environ["OSORI_NAME"].strip()
query = name.lower()

res = load_registry(os.environ["OSORI_REG"], auto_migrate=True, make_backup_on_migrate=True)
projects = registry_projects(res.registry)

# 1) Registry lookup
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

# 2) Spotlight (macOS)
if shutil.which('mdfind'):
    r = subprocess.run(['mdfind', f'kMDItemFSName == "{name}"'], capture_output=True, text=True)
    if r.stdout.strip():
        print("🔍 *Found via Spotlight:*")
        for p in r.stdout.strip().split('\n')[:3]:
            print(f"📍 {p}")
        raise SystemExit(0)

# 3) find fallback
search_paths = os.environ.get('OSORI_SEARCH_PATHS', '/Volumes/eyedisk/develop').split(':')
for sp in search_paths:
    if not os.path.exists(sp):
        continue
    r = subprocess.run(
        ['find', sp, '-maxdepth', '4', '-type', 'd', '-name', f'*{name}*'],
        capture_output=True, text=True, timeout=10,
    )
    if r.stdout.strip():
        print("🔍 *Found via search:*")
        for p in r.stdout.strip().split('\n')[:3]:
            print(f"📍 {p}")
        raise SystemExit(0)

print(f"❌ Project '{name}' not found.")
PYSCRIPT
}

cmd_switch() {
    local name="${1:-}"
    [[ -z "$name" ]] && { echo "❌ Usage: /switch <project-name>"; exit 1; }

    OSORI_NAME="$name" OSORI_SCRIPT_DIR="$SCRIPT_DIR" OSORI_REG="$REGISTRY_FILE" python3 << 'PYSCRIPT'
import json
import os
import shutil
import subprocess
import sys

sys.path.insert(0, os.environ["OSORI_SCRIPT_DIR"])
from registry_lib import load_registry, parse_repo_from_remote, registry_projects


def run(cmd, timeout=8):
    try:
        p = subprocess.run(cmd, capture_output=True, text=True, timeout=timeout)
        return p.returncode, p.stdout.strip(), p.stderr.strip()
    except Exception as e:
        return 1, "", str(e)


def gh_count(kind, repo):
    if not repo or shutil.which("gh") is None:
        return "n/a"
    rc, out, _ = run(["gh", kind, "list", "-R", repo, "--state", "open", "--json", "number", "--limit", "200"], timeout=12)
    if rc != 0 or not out:
        return "n/a"
    try:
        return str(len(json.loads(out)))
    except Exception:
        return "n/a"

name = os.environ["OSORI_NAME"].strip().lower()
res = load_registry(os.environ["OSORI_REG"], auto_migrate=True, make_backup_on_migrate=True)
projects = registry_projects(res.registry)

target = None
for p in projects:
    if name in p.get('name', '').lower():
        target = p
        break

if not target:
    print(f"❌ Project '{os.environ['OSORI_NAME']}' not found in registry.")
    raise SystemExit(1)

path = target.get('path', '')
if not path or not os.path.exists(path):
    print(f"⚠️ Path does not exist: {path}")
    raise SystemExit(1)

print(f"📁 *{target.get('name')}*")
print(f"📍 {path}")
print(f"🧭 root: {target.get('root', 'default')}")

# git status
rc, status_out, _ = run(['git', '-C', path, 'status', '--short'])
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
    local query="${1:-}"
    bash "$SCRIPT_DIR/project-fingerprints.sh" "$query"
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
    local path="${1:-/Volumes/eyedisk/develop}"
    [[ ! -d "$path" ]] && { echo "❌ Directory not found: $path"; exit 1; }

    echo "🔍 *Scanning for git repositories...*"
    bash "$SCRIPT_DIR/scan-projects.sh" "$path" --depth 2
}

# Main dispatch
case "${1:-help}" in
    list) cmd_list ;;
    status) cmd_status ;;
    find) cmd_find "${2:-}" ;;
    switch) cmd_switch "${2:-}" ;;
    fingerprints) cmd_fingerprints "${2:-}" ;;
    add) cmd_add "${2:-}" ;;
    remove) cmd_remove "${2:-}" ;;
    scan) cmd_scan "${2:-}" ;;
    help|--help|-h) show_help ;;
    *) echo "❌ Unknown command: $1"; show_help; exit 1 ;;
esac