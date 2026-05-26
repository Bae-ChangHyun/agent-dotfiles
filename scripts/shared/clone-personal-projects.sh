#!/usr/bin/env bash
# 본인 프로젝트 git clone + 초기 setup.
# manifests/personal-projects.json 읽음.
set -euo pipefail

REPO_ROOT="${REPO_ROOT:-$HOME/.local/share/chezmoi}"
MANIFEST="$REPO_ROOT/manifests/personal-projects.json"

log() { printf '\033[1;32m[clone]\033[0m %s\n' "$*"; }

command -v jq >/dev/null 2>&1 || { log "❌ jq 필요"; exit 1; }

# 환경변수 expand (PROJECTS_ROOT 없으면 ~/Project/sub_project/personal)
RENDERED=$(envsubst < "$MANIFEST" 2>/dev/null || cat "$MANIFEST" | sed "s|\${PROJECTS_ROOT:-\$HOME[^}]*}|${PROJECTS_ROOT:-$HOME/Project/sub_project/personal}|g")

jq -c '.projects[]' <<< "$RENDERED" | while read -r p; do
    name=$(echo "$p" | jq -r '.name')
    repo=$(echo "$p" | jq -r '.repo')
    path=$(echo "$p" | jq -r '.path')

    if [[ "$repo" == TODO:* ]]; then
        log "⊘ $name — repo URL 미설정 (manifests/personal-projects.json 수정 필요)"
        continue
    fi

    if [[ -d "$path/.git" ]]; then
        log "✓ $name 이미 있음 — pull"
        git -C "$path" pull --ff-only 2>&1 | sed 's/^/    /' || true
    else
        log "+ $name clone → $path"
        mkdir -p "$(dirname "$path")"
        if [[ "$repo" == http* ]] || [[ "$repo" == git@* ]]; then
            git clone "$repo" "$path"
        else
            gh repo clone "$repo" "$path"
        fi
    fi

    # setup 명령 실행
    setup_cmds=$(echo "$p" | jq -r '.setup[]?' 2>/dev/null || true)
    if [[ -n "$setup_cmds" ]]; then
        cd "$path"
        while IFS= read -r cmd; do
            [[ -z "$cmd" ]] && continue
            log "  ▶ $cmd"
            eval "$cmd" 2>&1 | sed 's/^/    /' || true
        done <<< "$setup_cmds"
    fi
done

log "✓ 개인 프로젝트 셋업 완료"
