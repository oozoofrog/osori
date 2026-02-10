#!/usr/bin/env bash
# Simple test runner for osori scripts
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
PASSED=0
FAILED=0
ERRORS=()

RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m'

assert_eq() {
  local desc="$1" expected="$2" actual="$3"
  if [[ "$expected" == "$actual" ]]; then
    echo -e "  ${GREEN}✓${NC} $desc"; PASSED=$((PASSED + 1))
  else
    echo -e "  ${RED}✗${NC} $desc"; echo "    expected: $expected"; echo "    actual:   $actual"
    FAILED=$((FAILED + 1)); ERRORS+=("$desc")
  fi
}
assert_contains() {
  local desc="$1" haystack="$2" needle="$3"
  if [[ "$haystack" == *"$needle"* ]]; then
    echo -e "  ${GREEN}✓${NC} $desc"; PASSED=$((PASSED + 1))
  else
    echo -e "  ${RED}✗${NC} $desc"; echo "    expected to contain: $needle"; echo "    actual: $haystack"
    FAILED=$((FAILED + 1)); ERRORS+=("$desc")
  fi
}
assert_not_contains() {
  local desc="$1" haystack="$2" needle="$3"
  if [[ "$haystack" != *"$needle"* ]]; then
    echo -e "  ${GREEN}✓${NC} $desc"; PASSED=$((PASSED + 1))
  else
    echo -e "  ${RED}✗${NC} $desc"; echo "    expected NOT to contain: $needle"
    FAILED=$((FAILED + 1)); ERRORS+=("$desc")
  fi
}
assert_file_exists() {
  local desc="$1" file="$2"
  if [[ -f "$file" ]]; then
    echo -e "  ${GREEN}✓${NC} $desc"; PASSED=$((PASSED + 1))
  else
    echo -e "  ${RED}✗${NC} $desc"; echo "    file not found: $file"
    FAILED=$((FAILED + 1)); ERRORS+=("$desc")
  fi
}

setup_test() {
  TEST_TMP="$(mktemp -d)"
  mkdir -p "$TEST_TMP/fake-project"
  git -C "$TEST_TMP/fake-project" init -q 2>/dev/null || true
  export OSORI_REGISTRY="$TEST_TMP/osori.json"
}
teardown_test() { rm -rf "$TEST_TMP"; unset OSORI_REGISTRY; }

# ─── TESTS ───

echo "=== test_add_project ==="
setup_test
output=$(bash "$PROJECT_ROOT/scripts/add-project.sh" "$TEST_TMP/fake-project" --name "myproject" 2>&1)
assert_contains "add prints Added" "$output" "Added"
assert_file_exists "registry created" "$TEST_TMP/osori.json"
content=$(cat "$TEST_TMP/osori.json")
assert_contains "registry has project name" "$content" '"myproject"'
assert_contains "registry has path" "$content" "$TEST_TMP/fake-project"
teardown_test

echo ""
echo "=== test_add_duplicate ==="
setup_test
bash "$PROJECT_ROOT/scripts/add-project.sh" "$TEST_TMP/fake-project" --name "duptest" >/dev/null 2>&1
output=$(bash "$PROJECT_ROOT/scripts/add-project.sh" "$TEST_TMP/fake-project" --name "duptest" 2>&1)
assert_contains "duplicate detected" "$output" "Already registered"
count=$(python3 -c "import json; print(len(json.load(open('$TEST_TMP/osori.json'))))")
assert_eq "only one entry" "1" "$count"
teardown_test

echo ""
echo "=== test_scan_projects ==="
setup_test
for name in proj-a proj-b proj-c; do
  mkdir -p "$TEST_TMP/repos/$name"
  git -C "$TEST_TMP/repos/$name" init -q 2>/dev/null
done
output=$(bash "$PROJECT_ROOT/scripts/scan-projects.sh" "$TEST_TMP/repos" --depth 2 2>&1)
assert_contains "scan reports additions" "$output" "Added 3"
count=$(python3 -c "import json; print(len(json.load(open('$TEST_TMP/osori.json'))))")
assert_eq "three projects registered" "3" "$count"
teardown_test

echo ""
echo "=== test_injection_safe ==="
setup_test
mkdir -p "$TEST_TMP/evil-project"
git -C "$TEST_TMP/evil-project" init -q 2>/dev/null
EVIL_NAME='test"; rm -rf /; echo "'
bash "$PROJECT_ROOT/scripts/add-project.sh" "$TEST_TMP/evil-project" --name "$EVIL_NAME" 2>&1 || true
valid=$(python3 -c "
import json
try:
    json.load(open('$TEST_TMP/osori.json'))
    print('valid')
except:
    print('invalid')
" 2>/dev/null || echo "invalid")
assert_eq "registry is valid JSON after injection attempt" "valid" "$valid"

mkdir -p "$TEST_TMP/backtick-project"
git -C "$TEST_TMP/backtick-project" init -q 2>/dev/null
cat > "$TEST_TMP/backtick-project/package.json" << 'PKGJSON'
{"description": "test `whoami` $(id) injection"}
PKGJSON
bash "$PROJECT_ROOT/scripts/add-project.sh" "$TEST_TMP/backtick-project" --name "backtick-test" 2>&1 || true
valid2=$(python3 -c "
import json
try:
    json.load(open('$TEST_TMP/osori.json'))
    print('valid')
except:
    print('invalid')
" 2>/dev/null || echo "invalid")
assert_eq "registry valid after backtick injection" "valid" "$valid2"
teardown_test

echo ""
echo "=== test_registry_env ==="
setup_test
CUSTOM_PATH="$TEST_TMP/custom/path/registry.json"
export OSORI_REGISTRY="$CUSTOM_PATH"
bash "$PROJECT_ROOT/scripts/add-project.sh" "$TEST_TMP/fake-project" --name "envtest" >/dev/null 2>&1
assert_file_exists "registry at custom env path" "$CUSTOM_PATH"
content=$(cat "$CUSTOM_PATH")
assert_contains "project in custom registry" "$content" '"envtest"'
teardown_test

echo ""
echo "=== test_no_hardcoded_paths ==="
skill_content=$(cat "$PROJECT_ROOT/SKILL.md")
assert_not_contains "no /Volumes/eyedisk in SKILL.md" "$skill_content" "/Volumes/eyedisk"
assert_not_contains "no ~/Developer in SKILL.md" "$skill_content" "~/Developer"
for script in "$PROJECT_ROOT/scripts/"*.sh; do
  sc=$(cat "$script")
  sname=$(basename "$script")
  assert_not_contains "no hardcoded relative registry in $sname" "$sc" '"$(dirname "$0")/../osori.json"'
done

echo ""
echo "=== test_platform_notes ==="
skill_content=$(cat "$PROJECT_ROOT/SKILL.md")
assert_contains "SKILL.md mentions mdfind is macOS only" "$skill_content" "macOS"
assert_contains "SKILL.md mentions python3 dependency" "$skill_content" "python3"

# Summary
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo -e "Results: ${GREEN}$PASSED passed${NC}, ${RED}$FAILED failed${NC}"
if [[ $FAILED -gt 0 ]]; then
  echo "Failed tests:"
  for e in "${ERRORS[@]}"; do echo "  - $e"; done
  exit 1
fi
echo "All tests passed! ✓"
