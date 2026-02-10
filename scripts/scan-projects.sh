#!/usr/bin/env bash
# Scan a directory for git repos and add them to the registry
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

REGISTRY_FILE="${OSORI_REGISTRY:-$HOME/.openclaw/osori.json}"

# Ensure parent directory exists
mkdir -p "$(dirname "$REGISTRY_FILE")"

# Init registry if missing
if [[ ! -f "$REGISTRY_FILE" ]]; then
  echo "[]" > "$REGISTRY_FILE"
fi

# Collect entries as a temp JSON file
TMPFILE="$(mktemp)"
echo "[]" > "$TMPFILE"
trap 'rm -f "$TMPFILE"' EXIT

# Load existing names
EXISTING_NAMES=$(OSORI_REG="$REGISTRY_FILE" python3 << 'PYEOF'
import json, os
with open(os.environ["OSORI_REG"]) as f:
    data = json.load(f)
for p in data:
    print(p["name"])
PYEOF
) || true

while IFS= read -r gitdir; do
  dir="$(dirname "$gitdir")"
  name="$(basename "$dir")"

  # Skip if already registered
  if echo "$EXISTING_NAMES" | grep -qx "$name"; then
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

  # Detect description safely
  desc=""
  if [[ -f "$dir/package.json" ]]; then
    desc=$(python3 -c "import json,sys; print(json.load(sys.stdin).get('description',''))" < "$dir/package.json" 2>/dev/null || true)
  fi

  # Detect tag from parent dir
  parent="$(basename "$(dirname "$dir")")"
  today=$(date +%Y-%m-%d)

  # Append entry to tmpfile via env vars
  OSORI_TMPFILE="$TMPFILE" \
  OSORI_NAME="$name" \
  OSORI_PATH="$dir" \
  OSORI_REPO="$repo" \
  OSORI_LANG="$lang" \
  OSORI_TAG="$parent" \
  OSORI_DESC="$desc" \
  OSORI_TODAY="$today" \
  python3 << 'PYEOF'
import json, os

tmpfile = os.environ["OSORI_TMPFILE"]
with open(tmpfile) as f:
    entries = json.load(f)

entries.append({
    "name": os.environ["OSORI_NAME"],
    "path": os.environ["OSORI_PATH"],
    "repo": os.environ["OSORI_REPO"],
    "lang": os.environ["OSORI_LANG"],
    "tags": [os.environ["OSORI_TAG"]],
    "description": os.environ["OSORI_DESC"],
    "addedAt": os.environ["OSORI_TODAY"]
})

with open(tmpfile, "w") as f:
    json.dump(entries, f)
PYEOF

done < <(find "$ROOT" -maxdepth "$DEPTH" -name '.git' -type d 2>/dev/null)

# Merge with existing registry
OSORI_REG="$REGISTRY_FILE" \
OSORI_TMPFILE="$TMPFILE" \
python3 << 'PYEOF'
import json, os

reg_file = os.environ["OSORI_REG"]
tmpfile = os.environ["OSORI_TMPFILE"]

with open(reg_file) as f:
    existing = json.load(f)
with open(tmpfile) as f:
    new_entries = json.load(f)

existing.extend(new_entries)
with open(reg_file, "w") as f:
    json.dump(existing, f, indent=2, ensure_ascii=False)
print(f"Added {len(new_entries)} projects. Total: {len(existing)}")
PYEOF
