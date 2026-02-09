#!/usr/bin/env bash
# Scan a directory for git repos and output JSON registry entries
# Usage: scan-projects.sh <root-dir> [--depth N]

set -euo pipefail

ROOT="${1:-.}"
DEPTH=3

shift || true
while [[ $# -gt 0 ]]; do
  case "$1" in
    --depth) DEPTH="$2"; shift 2 ;;
    *) shift ;;
  esac
done

REGISTRY_FILE="$(dirname "$0")/../osori.json"

# Load existing names to avoid duplicates
existing_names=""
if [[ -f "$REGISTRY_FILE" ]]; then
  existing_names=$(python3 -c "
import json, sys
with open('$REGISTRY_FILE') as f:
    data = json.load(f)
for p in data:
    print(p['name'])
" 2>/dev/null || true)
fi

# Find git repos
entries="[]"
while IFS= read -r gitdir; do
  dir="$(dirname "$gitdir")"
  name="$(basename "$dir")"
  
  # Skip if already registered
  if echo "$existing_names" | grep -qx "$name"; then
    continue
  fi

  # Detect remote
  repo=""
  remote=$(git -C "$dir" remote get-url origin 2>/dev/null || true)
  if [[ "$remote" =~ github\.com[:/]([^/]+/[^/.]+) ]]; then
    repo="${BASH_REMATCH[1]}"
  fi

  # Detect language
  lang="unknown"
  if [[ -f "$dir/Package.swift" ]]; then lang="swift"
  elif [[ -f "$dir/package.json" ]]; then lang="typescript"
  elif [[ -f "$dir/Cargo.toml" ]]; then lang="rust"
  elif [[ -f "$dir/go.mod" ]]; then lang="go"
  elif [[ -f "$dir/pyproject.toml" ]] || [[ -f "$dir/setup.py" ]]; then lang="python"
  elif [[ -f "$dir/Gemfile" ]]; then lang="ruby"
  fi

  # Detect description
  desc=""
  if [[ -f "$dir/package.json" ]]; then
    desc=$(python3 -c "import json; print(json.load(open('$dir/package.json')).get('description',''))" 2>/dev/null || true)
  fi

  # Detect org/tag from path
  parent="$(basename "$(dirname "$dir")")"
  tag="$parent"

  today=$(date +%Y-%m-%d)

  entries=$(python3 -c "
import json, sys
entries = json.loads('''$entries''')
entries.append({
    'name': '$name',
    'path': '$dir',
    'repo': '$repo',
    'lang': '$lang',
    'tags': ['$tag'],
    'description': '''$desc''',
    'addedAt': '$today'
})
print(json.dumps(entries))
")

done < <(find "$ROOT" -maxdepth "$DEPTH" -name '.git' -type d 2>/dev/null)

# Merge with existing
if [[ -f "$REGISTRY_FILE" ]]; then
  python3 -c "
import json
with open('$REGISTRY_FILE') as f:
    existing = json.load(f)
new_entries = json.loads('''$entries''')
existing.extend(new_entries)
with open('$REGISTRY_FILE', 'w') as f:
    json.dump(existing, f, indent=2, ensure_ascii=False)
print(f'Added {len(new_entries)} projects. Total: {len(existing)}')
"
else
  python3 -c "
import json
entries = json.loads('''$entries''')
with open('$REGISTRY_FILE', 'w') as f:
    json.dump(entries, f, indent=2, ensure_ascii=False)
print(f'Created registry with {len(entries)} projects.')
"
fi
