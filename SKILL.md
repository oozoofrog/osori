---
name: osori
description: "Osori — Local project registry & context loader. Find, switch, list, add/remove projects, check status. | 오소리 — 로컬 프로젝트 레지스트리 및 컨텍스트 로더. Triggers: 프로젝트 찾아, 프로젝트 목록, 작업하자, 프로젝트 추가, 프로젝트 상태, work on X, find project X, list projects, project status, project switch."
---

# 오소리 (Osori)

Local project registry & context loader.
로컬 프로젝트 레지스트리 및 컨텍스트 로더.

## Prerequisites

- **macOS**: `mdfind` (Spotlight, built-in), `python3`, `git`, `gh` CLI
- **Linux**: `mdfind` unavailable → uses `find` as fallback automatically. `python3`, `git`, `gh` CLI required.

## Dependencies

- **python3** — 필수. JSON 처리에 사용.
- **git** — 프로젝트 감지 및 상태 확인.

## Registry

`${OSORI_REGISTRY:-$HOME/.openclaw/osori.json}`

환경변수 `OSORI_REGISTRY`로 커스텀 경로 설정 가능.

## 프로젝트 찾기 (경로를 모를 때)

프로젝트 경로를 모르면 다음 순서로 탐색:

1. **레지스트리 검색** — `osori.json`에서 이름 fuzzy match
2. **mdfind 탐색** (macOS) — `mdfind "kMDItemFSName == '<name>'" | head -5`
3. **find 탐색** — `OSORI_SEARCH_PATHS` 환경변수에 지정된 경로를 탐색. 미설정 시 사용자에게 검색 경로를 질문.
   `find <search_paths> -maxdepth 4 -type d -name '<name>' 2>/dev/null`
4. **사용자에게 질문** — 위 방법으로 못 찾으면 "프로젝트 경로를 알려주세요" 요청
5. 찾으면 자동으로 레지스트리에 등록 제안

## Commands

### 목록 (list)
레지스트리의 모든 프로젝트 표시. `--tag`, `--lang` 필터 가능.
```
osori.json 읽어서 테이블 형태로 출력
```

### 전환 (switch)
1. 레지스트리에서 프로젝트 검색 (fuzzy match)
2. 없으면 → 위 "프로젝트 찾기" 흐름 실행
3. 찾으면 컨텍스트 로드:
   - `git status --short`
   - `git branch --show-current`
   - `git log --oneline -5`
   - `gh issue list -R <repo> --limit 5` (repo 있을 때)
4. 요약 출력

### 추가 (add)
```bash
bash skills/osori/scripts/add-project.sh <path> [--tag <tag>] [--name <name>]
```
Auto-detect: git remote, language, description.

### 스캔 (scan)
```bash
bash skills/osori/scripts/scan-projects.sh <root-dir> [--depth 3]
```
디렉토리 일괄 스캔 후 레지스트리에 추가.

### 제거 (remove)
`osori.json`에서 이름으로 항목 삭제.

### 상태 (status)
하나 또는 모든 프로젝트의 `git status` + `gh issue list` 실행.

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

## 자동 트리거 규칙 / Auto-trigger Rules

- "X 프로젝트 작업하자" / "work on X" → switch X
- "X 찾아줘" / "X 경로" / "find project X" → 레지스트리 검색 or 탐색
- "프로젝트 목록" / "list projects" → list
- "프로젝트 추가" → add
- "프로젝트 상태" / "project status" → status all
