#!/usr/bin/env bash
# 현재 PC의 Claude 상태(플러그인/마켓플레이스/MCP)를 읽어서 manifests/* 재생성.
set -euo pipefail

REPO="$HOME/.local/share/chezmoi"
C_OK=$(tput setaf 2 2>/dev/null || echo "")
C_DIM=$(tput setaf 8 2>/dev/null || echo "")
C_OFF=$(tput sgr0 2>/dev/null || echo "")

# ---- 1. 마켓플레이스 ----
SRC_MKT="$HOME/.claude/plugins/known_marketplaces.json"
OUT_MKT="$REPO/manifests/claude/marketplaces.json"
if [[ -f "$SRC_MKT" ]]; then
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
    n=$(jq '.marketplaces | length' "$OUT_MKT")
    printf '  %s✓%s 마켓플레이스: %d개\n' "$C_OK" "$C_OFF" "$n"
fi

# ---- 2. 플러그인 (user scope) ----
SRC_PLG="$HOME/.claude/plugins/installed_plugins.json"
OUT_PLG="$REPO/manifests/claude/plugins.txt"
if [[ -f "$SRC_PLG" ]]; then
    {
        echo "# 자동 생성됨 by sync-manifests.sh — user scope 플러그인만"
        echo ""
        jq -r '
            .plugins | to_entries[] |
            .key as $name |
            (.value | map(select(.scope == "user")) | first) as $entry |
            if $entry then "\($name)\tuser" else empty end
        ' "$SRC_PLG" | column -t
    } > "$OUT_PLG"
    n=$(grep -cvE "^\s*(#|$)" "$OUT_PLG" || echo 0)
    printf '  %s✓%s user-scope 플러그인: %d개\n' "$C_OK" "$C_OFF" "$n"
fi

# ---- 3. MCP 서버 ----
SRC_MCP="$HOME/.claude.json"
OUT_MCP="$REPO/manifests/claude/mcp.json"
if [[ -f "$SRC_MCP" ]]; then
    jq --arg home "$HOME" '{
        "$comment": "자동 생성됨 by sync-manifests.sh — ~/.claude.json mcpServers 기반",
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
    n=$(jq '.servers | length' "$OUT_MCP")
    printf '  %s✓%s MCP 서버 (Claude): %d개\n' "$C_OK" "$C_OFF" "$n"
fi

printf '  %sCodex MCP는 ~/.codex/config.toml 안에 있어서 chezmoi re-add로 자동 sync%s\n' "$C_DIM" "$C_OFF"
