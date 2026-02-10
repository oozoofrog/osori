#!/usr/bin/env bash
# Add a single project to the registry
# Usage: add-project.sh <path> [--tag <tag>] [--name <name>]

set -euo pipefail

PROJECT_PATH="$(cd "$1" && pwd)"
shift

NAME="$(basename "$PROJECT_PATH")"
TAG=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --tag) TAG="$2"; shift 2 ;;
    --name) NAME="$2"; shift 2 ;;
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

# Detect remote
REPO=""
REMOTE=$(git -C "$PROJECT_PATH" remote get-url origin 2>/dev/null || true)
if [[ "$REMOTE" =~ github\.com[:/]([^/]+/[^/.]+) ]]; then
  REPO="${BASH_REMATCH[1]}"
fi

# Detect language
LANG_DETECTED="unknown"
if [[ -f "$PROJECT_PATH/Package.swift" ]]; then LANG_DETECTED="swift"
elif [[ -f "$PROJECT_PATH/package.json" ]]; then LANG_DETECTED="typescript"
elif [[ -f "$PROJECT_PATH/Cargo.toml" ]]; then LANG_DETECTED="rust"
elif [[ -f "$PROJECT_PATH/go.mod" ]]; then LANG_DETECTED="go"
elif [[ -f "$PROJECT_PATH/pyproject.toml" ]] || [[ -f "$PROJECT_PATH/setup.py" ]]; then LANG_DETECTED="python"
fi

# Detect description safely via stdin
DESC=""
if [[ -f "$PROJECT_PATH/package.json" ]]; then
  DESC=$(python3 -c "import json,sys; print(json.load(sys.stdin).get('description',''))" < "$PROJECT_PATH/package.json" 2>/dev/null || true)
fi

TODAY=$(date +%Y-%m-%d)

# Build and merge entry safely — all variables via environment, not shell interpolation
OSORI_NAME="$NAME" \
OSORI_PATH="$PROJECT_PATH" \
OSORI_REPO="$REPO" \
OSORI_LANG="$LANG_DETECTED" \
OSORI_TAG="$TAG" \
OSORI_DESC="$DESC" \
OSORI_TODAY="$TODAY" \
OSORI_REG="$REGISTRY_FILE" \
python3 << 'PYEOF'
import json, os

reg_file = os.environ["OSORI_REG"]
name = os.environ["OSORI_NAME"]
path = os.environ["OSORI_PATH"]
repo = os.environ["OSORI_REPO"]
lang = os.environ["OSORI_LANG"]
tag = os.environ["OSORI_TAG"]
desc = os.environ["OSORI_DESC"]
today = os.environ["OSORI_TODAY"]

with open(reg_file) as f:
    data = json.load(f)

for p in data:
    if p["name"] == name:
        print(f"Already registered: {name}")
        exit(0)

tags = [tag] if tag else []
data.append({
    "name": name,
    "path": path,
    "repo": repo,
    "lang": lang,
    "tags": tags,
    "description": desc,
    "addedAt": today
})

with open(reg_file, "w") as f:
    json.dump(data, f, indent=2, ensure_ascii=False)
print(f"Added: {name} ({path})")
PYEOF
