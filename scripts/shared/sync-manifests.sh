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
# 절대경로 → placeholder 자동 역치환:
#   $PROJECTS_ROOT  → {{PROJECTS_ROOT}}     (있는 경우)
#   $OBSIDIAN_SYNC  → {{OBSIDIAN_VAULT}}    (있는 경우)
#   $HOME           → {{HOME}}              (항상)
# 각 PC의 ~/.config/agent-dotfiles/env에 PROJECTS_ROOT, OBSIDIAN_SYNC 정의 시,
# install-mcp.sh가 pull 시 자동으로 그 PC 경로로 expand.
SRC_MCP="$HOME/.claude.json"
OUT_MCP="$REPO/manifests/claude/mcp.json"
if [[ -f "$SRC_MCP" ]]; then
    # 머신별 env 로드 (PROJECTS_ROOT 등)
    [[ -f "$HOME/.config/agent-dotfiles/env" ]] && source "$HOME/.config/agent-dotfiles/env" || true

    jq --arg home "$HOME" \
       --arg pr "${PROJECTS_ROOT:-}" \
       --arg ov "${OBSIDIAN_SYNC:-}" '{
        "$comment": "자동 생성. {{HOME}}/{{PROJECTS_ROOT}}/{{OBSIDIAN_VAULT}}는 install-mcp.sh가 각 PC env로 expand.",
        servers: [
            (.mcpServers // {}) | to_entries[] | {
                name: .key,
                type: (.value.type // "stdio"),
                scope: "user",
                command: (.value.command // null),
                args: (
                    if .value.args then
                        .value.args | map(
                            (if $pr != "" then gsub($pr; "{{PROJECTS_ROOT}}") else . end) |
                            (if $ov != "" then gsub($ov; "{{OBSIDIAN_VAULT}}") else . end) |
                            gsub($home; "{{HOME}}")
                        )
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
