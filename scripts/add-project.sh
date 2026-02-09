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

REGISTRY_FILE="$(dirname "$0")/../projects.json"

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
LANG="unknown"
if [[ -f "$PROJECT_PATH/Package.swift" ]]; then LANG="swift"
elif [[ -f "$PROJECT_PATH/package.json" ]]; then LANG="typescript"
elif [[ -f "$PROJECT_PATH/Cargo.toml" ]]; then LANG="rust"
elif [[ -f "$PROJECT_PATH/go.mod" ]]; then LANG="go"
elif [[ -f "$PROJECT_PATH/pyproject.toml" ]] || [[ -f "$PROJECT_PATH/setup.py" ]]; then LANG="python"
fi

# Detect description
DESC=""
if [[ -f "$PROJECT_PATH/package.json" ]]; then
  DESC=$(python3 -c "import json; print(json.load(open('$PROJECT_PATH/package.json')).get('description',''))" 2>/dev/null || true)
fi

TODAY=$(date +%Y-%m-%d)
TAGS_JSON="[]"
if [[ -n "$TAG" ]]; then
  TAGS_JSON="[\"$TAG\"]"
fi

python3 -c "
import json
with open('$REGISTRY_FILE') as f:
    data = json.load(f)

# Check duplicate
for p in data:
    if p['name'] == '$NAME':
        print(f'Already registered: $NAME')
        exit(0)

data.append({
    'name': '$NAME',
    'path': '$PROJECT_PATH',
    'repo': '$REPO',
    'lang': '$LANG',
    'tags': json.loads('$TAGS_JSON'),
    'description': '''$DESC''',
    'addedAt': '$TODAY'
})

with open('$REGISTRY_FILE', 'w') as f:
    json.dump(data, f, indent=2, ensure_ascii=False)
print(f'Added: $NAME ($PROJECT_PATH)')
"
