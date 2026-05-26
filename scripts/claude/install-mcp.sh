#!/usr/bin/env bash
# Claude Code MCP 서버 등록.
# manifests/claude/mcp.json 읽음.
set -euo pipefail

REPO_ROOT="${REPO_ROOT:-$HOME/.local/share/chezmoi}"
MCP_JSON="$REPO_ROOT/manifests/claude/mcp.json"

log() { printf '\033[1;35m[claude/mcp]\033[0m %s\n' "$*"; }

if ! command -v claude >/dev/null 2>&1; then
    log "❌ claude CLI 없음"; exit 1
fi
if ! command -v jq >/dev/null 2>&1; then
    log "❌ jq 필요"; exit 1
fi

count=$(jq '.servers | length' "$MCP_JSON")
log "Claude MCP 서버 $count 개 처리"

jq -c '.servers[]' "$MCP_JSON" | while read -r srv; do
    name=$(echo "$srv" | jq -r '.name')
    type=$(echo "$srv" | jq -r '.type')
    scope=$(echo "$srv" | jq -r '.scope // "user"')
    skip=$(echo "$srv" | jq -r '.skip // false')

    if [[ "$skip" == "true" ]]; then
        manual=$(echo "$srv" | jq -r '.manualInstruction // "수동 등록 필요"')
        log "  ⊘ $name — $manual"
        continue
    fi

    case "$type" in
        stdio)
            command=$(echo "$srv" | jq -r '.command')
            args=$(echo "$srv" | jq -r '.args | map(. | gsub("{{HOME}}"; env.HOME)) | join(" ")')
            requires=$(echo "$srv" | jq -r '.requiresProject // ""')
            if [[ -n "$requires" ]]; then
                if [[ ! -d "$HOME/Project/sub_project/personal/$requires" ]]; then
                    log "  ⊘ $name — 의존 프로젝트 '$requires' 없음. clone-personal-projects.sh 먼저 실행"
                    continue
                fi
            fi
            log "  + $name (stdio): $command $args"
            claude mcp add "$name" --scope "$scope" -- $command $args 2>&1 | sed 's/^/    /' || true
            ;;
        http)
            url=$(echo "$srv" | jq -r '.url')
            if [[ "$url" == TODO:* ]]; then
                log "  ⊘ $name — URL 미설정 (manifests/claude/mcp.json 참고)"
                continue
            fi
            log "  + $name (http): $url"
            claude mcp add "$name" --scope "$scope" --transport http "$url" 2>&1 | sed 's/^/    /' || true
            ;;
        *)
            log "  ? $name — 알 수 없는 type: $type"
            ;;
    esac
done

log "✓ Claude MCP 등록 완료"
