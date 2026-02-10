#!/usr/bin/env bash
# Telegram bot command handler for osori
# Usage: telegram-commands.sh <command> [args...]

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REGISTRY_FILE="${OSORI_REGISTRY:-$HOME/.openclaw/osori.json}"

# Ensure registry exists
if [[ ! -f "$REGISTRY_FILE" ]]; then
    echo "[]" > "$REGISTRY_FILE"
fi

show_help() {
    cat << 'EOF'
🦦 *Osori Bot Commands*

/list — Show all projects
/status — Check all project statuses  
/find \<name\> — Find a project path
/switch \<name\> — Switch to project \u0026 load context
/add \<path\> — Add project to registry
/remove \<name\> — Remove project from registry
/scan \<path\> — Scan directory for projects
/help — Show this help

*Examples:*
`/find agent-avengers`
`/switch Tesella`
`/add /Volumes/disk/MyProject`
EOF
}

cmd_list() {
    python3 << 'PYSCRIPT'
import json
import os

registry = os.path.expanduser("~/.openclaw/osori.json")
if not os.path.exists(registry):
    print("📂 No projects registered yet.")
    exit(0)

with open(registry) as f:
    projects = json.load(f)

if not projects:
    print("📂 No projects registered yet.")
    exit(0)

print(f"📋 *{len(projects)} Projects*\n")

for p in projects[:20]:  # Limit to 20 for Telegram
    name = p['name']
    lang = p.get('lang', '-')
    tags = ', '.join(p.get('tags', [])) or '-'
    repo = p.get('repo', '')
    
    repo_str = f" | 🌐 {repo}" if repo else ""
    print(f"• *{name}* | {lang} | {tags}{repo_str}")

if len(projects) > 20:
    print(f"\n... and {len(projects) - 20} more")
PYSCRIPT
}

cmd_status() {
    python3 << 'PYSCRIPT'
import json
import os
import subprocess

registry = os.path.expanduser("~/.openclaw/osori.json")
if not os.path.exists(registry):
    print("📂 No projects registered.")
    exit(0)

with open(registry) as f:
    projects = json.load(f)

clean = modified = missing = 0

for p in projects:
    path = p['path']
    name = p['name']
    
    if not os.path.exists(path):
        missing += 1
        continue
    
    try:
        result = subprocess.run(
            ['git', '-C', path, 'status', '--short'],
            capture_output=True, text=True, timeout=3
        )
        if result.stdout.strip():
            modified += 1
        else:
            clean += 1
    except:
        missing += 1

print(f"📊 *Project Status*\n")
print(f"✅ Clean: {clean}")
print(f"📝 Modified: {modified}")
print(f"⚠️ Missing: {missing}")
print(f"📁 Total: {len(projects)}")
PYSCRIPT
}

cmd_find() {
    local name="$1"
    [[ -z "$name" ]] && { echo "❌ Usage: /find \u003cproject-name\u003e"; exit 1; }
    
    python3 << PYSCRIPT
import json
import os
import subprocess
import sys

name = """$name"""
registry = os.path.expanduser("~/.openclaw/osori.json")

# 1. Registry lookup
if os.path.exists(registry):
    with open(registry) as f:
        projects = json.load(f)
    
    for p in projects:
        if name.lower() in p['name'].lower():
            print(f"📁 *{p['name']}*")
            print(f"📍 {p['path']}")
            if p.get('repo'):
                print(f"🌐 {p['repo']}")
            if p.get('lang') != 'unknown':
                print(f"🔤 {p['lang']}")
            sys.exit(0)

# 2. mdfind
result = subprocess.run(['mdfind', f'kMDItemFSName == "{name}"'], capture_output=True, text=True)
if result.stdout.strip():
    paths = result.stdout.strip().split('\n')[:3]
    print(f"🔍 *Found via Spotlight:*")
    for p in paths:
        print(f"📍 {p}")
    sys.exit(0)

# 3. find fallback
search_paths = os.environ.get('OSORI_SEARCH_PATHS', '/Volumes/eyedisk/develop').split(':')
for sp in search_paths:
    if os.path.exists(sp):
        result = subprocess.run(
            ['find', sp, '-maxdepth', '4', '-type', 'd', '-name', f'*{name}*'],
            capture_output=True, text=True, timeout=10
        )
        if result.stdout.strip():
            paths = result.stdout.strip().split('\n')[:3]
            print(f"🔍 *Found via search:*")
            for p in paths:
                print(f"📍 {p}")
            sys.exit(0)

print(f"❌ Project '{name}' not found.")
PYSCRIPT
}

cmd_switch() {
    local name="$1"
    [[ -z "$name" ]] && { echo "❌ Usage: /switch \u003cproject-name\u003e"; exit 1; }
    
    cmd_find "$name"
    
    # Load context if found
    python3 << PYSCRIPT
import json
import os
import subprocess
import sys

name = """$name""".lower()
registry = os.path.expanduser("~/.openclaw/osori.json")

if os.path.exists(registry):
    with open(registry) as f:
        projects = json.load(f)
    
    for p in projects:
        if name in p['name'].lower():
            path = p['path']
            if not os.path.exists(path):
                print(f"⚠️ Path does not exist: {path}")
                sys.exit(1)
            
            print(f"\n🔄 *Context for {p['name']}:*")
            
            # git status
            result = subprocess.run(['git', '-C', path, 'status', '--short'], 
                capture_output=True, text=True)
            if result.stdout.strip():
                print(f"\n📝 Changes:")
                for line in result.stdout.strip().split('\n')[:5]:
                    print(f"  {line}")
            else:
                print(f"\n✅ Clean working tree")
            
            # branch
            branch = subprocess.run(['git', '-C', path, 'branch', '--show-current'],
                capture_output=True, text=True).stdout.strip()
            print(f"\n🌿 Branch: {branch}")
            
            # recent commits
            log = subprocess.run(['git', '-C', path, 'log', '--oneline', '-3'],
                capture_output=True, text=True).stdout.strip()
            if log:
                print(f"\n💬 Recent commits:")
                for line in log.split('\n'):
                    print(f"  {line}")
            
            sys.exit(0)
PYSCRIPT
}

cmd_add() {
    local path="$1"
    [[ -z "$path" ]] && { echo "❌ Usage: /add \u003cpath\u003e"; exit 1; }
    [[ ! -d "$path" ]] && { echo "❌ Directory not found: $path"; exit 1; }
    
    bash "$SCRIPT_DIR/add-project.sh" "$path"
}

cmd_remove() {
    local name="$1"
    [[ -z "$name" ]] && { echo "❌ Usage: /remove \u003cproject-name\u003e"; exit 1; }
    
    python3 << PYSCRIPT
import json
import os

name = """$name"""
registry = os.path.expanduser("~/.openclaw/osori.json")

with open(registry) as f:
    projects = json.load(f)

original_len = len(projects)
projects = [p for p in projects if p['name'].lower() != name.lower()]

if len(projects) == original_len:
    print(f"❌ Project '{name}' not found.")
else:
    with open(registry, 'w') as f:
        json.dump(projects, f, indent=2, ensure_ascii=False)
    print(f"✅ Removed: {name}")
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
    add) cmd_add "${2:-}" ;;
    remove) cmd_remove "${2:-}" ;;
    scan) cmd_scan "${2:-}" ;;
    help|--help|-h) show_help ;;
    *) echo "❌ Unknown command: $1"; show_help; exit 1 ;;
esac
