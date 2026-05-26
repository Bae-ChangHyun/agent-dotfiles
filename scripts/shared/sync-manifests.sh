#!/usr/bin/env bash
# 현재 PC의 Claude 상태(플러그인/마켓플레이스/MCP)를 읽어서 manifests/* 재생성.
#
# 실행 후엔 `chezmoi cd && git diff manifests/` 로 변경 확인.
set -euo pipefail

REPO="$HOME/.local/share/chezmoi"
log() { printf '\033[1;33m[sync-manifest]\033[0m %s\n' "$*"; }

# ---- 1. 마켓플레이스 ----
SRC_MKT="$HOME/.claude/plugins/known_marketplaces.json"
OUT_MKT="$REPO/manifests/claude/marketplaces.json"
if [[ -f "$SRC_MKT" ]]; then
    log "마켓플레이스 → $OUT_MKT"
    jq '{
        "$comment": "자동 생성됨 by sync-manifests.sh — known_marketplaces.json 기반",
        marketplaces: [
            to_entries[] | {
                name: .key,
                repo: (.value.source.repo // null),
                url: (.value.source.url // null),
                autoUpdate: (.value.autoUpdate // false)
            } | with_entries(select(.value != null))
        ]
    }' "$SRC_MKT" > "$OUT_MKT"
fi

# ---- 2. 플러그인 ----
SRC_PLG="$HOME/.claude/plugins/installed_plugins.json"
OUT_PLG="$REPO/manifests/claude/plugins.txt"
if [[ -f "$SRC_PLG" ]]; then
    log "플러그인 → $OUT_PLG (user scope만)"
    {
        echo "# 자동 생성됨 by sync-manifests.sh"
        echo "# user scope 플러그인만 동기화 (project/local은 그 프로젝트 전용)"
        echo "# 형식: <plugin>@<marketplace>  <scope>"
        echo ""
        # user scope을 가진 항목만 추출 — project/local은 sync 대상 아님
        jq -r '
            .plugins | to_entries[] |
            .key as $name |
            (.value | map(select(.scope == "user")) | first) as $entry |
            if $entry then "\($name)\tuser" else empty end
        ' "$SRC_PLG" | column -t
    } > "$OUT_PLG"
fi

# ---- 3. MCP 서버 ----
SRC_MCP="$HOME/.claude.json"
OUT_MCP="$REPO/manifests/claude/mcp.json"
if [[ -f "$SRC_MCP" ]]; then
    log "MCP 서버 → $OUT_MCP"
    jq --arg home "$HOME" '{
        "$comment": "자동 생성됨 by sync-manifests.sh — ~/.claude.json mcpServers 기반",
        "$note": "절대 경로는 {{HOME}}으로 치환하여 PC 간 이식 가능",
        servers: [
            (.mcpServers // {}) | to_entries[] | {
                name: .key,
                type: (.value.type // "stdio"),
                scope: "user",
                command: (.value.command // null),
                args: (
                    if .value.args then
                        .value.args | map(gsub($home; "{{HOME}}"))
                    else null end
                ),
                url: (.value.url // null)
            } | with_entries(select(.value != null))
        ]
    }' "$SRC_MCP" > "$OUT_MCP"
fi

# ---- 4. Codex MCP (config.toml 안에 있음, re-add로 자동) ----
log "Codex MCP는 ~/.codex/config.toml 안에 있어서 chezmoi re-add로 동기화됨"

log "✓ manifest sync 완료"
log ""
log "다음 단계:"
log "  chezmoi cd && git diff manifests/"
log "  변경 OK 면 → git add -A && git commit -m '🔄 manifest sync' && git push"
