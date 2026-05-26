#!/usr/bin/env bash
# 현재 PC의 Claude 상태(플러그인/마켓플레이스/MCP)를 읽어서 manifests/* 재생성.
set -euo pipefail

REPO="$HOME/.local/share/chezmoi"
C_OK=$(tput setaf 2 2>/dev/null || echo "")
C_DIM=$(tput setaf 8 2>/dev/null || echo "")
C_OFF=$(tput sgr0 2>/dev/null || echo "")

# 머신별 env (있으면 source) — 사용자가 정의한 모든 export 변수 활용
[[ -f "$HOME/.config/agent-dotfiles/env" ]] && source "$HOME/.config/agent-dotfiles/env" || true

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
        echo "# 형식: <plugin>@<marketplace>  <scope>"
        echo ""
        # awk로 직접 정렬 (column -t 의존 X — macOS BSD vs GNU 호환성)
        jq -r '
            .plugins | to_entries[] |
            .key as $name |
            (.value | map(select(.scope == "user")) | first) as $entry |
            if $entry then "\($name)\tuser" else empty end
        ' "$SRC_PLG" | awk -F'\t' '{ printf "%-45s  %s\n", $1, $2 }'
    } > "$OUT_PLG"
    n=$(grep -cvE "^[[:space:]]*(#|$)" "$OUT_PLG" || echo 0)
    printf '  %s✓%s user-scope 플러그인: %d개\n' "$C_OK" "$C_OFF" "$n"
fi

# ---- 3. MCP 서버 ----
# 사용자가 env에 정의한 모든 변수의 값을 placeholder {{VARNAME}}로 역치환.
# 예: env에 FOO_PATH=$HOME/some/path 정의 시,
#     args 안의 "$HOME/some/path/..." → "{{FOO_PATH}}/..."
# 그리고 install-mcp.sh가 pull 시 그 PC의 env로 다시 expand.
# 추가로 $HOME → {{HOME}} 도 항상 처리.
# Claude Code 버전에 따라 .claude.json 위치 다름. 더 최신 수정시간 파일 우선.
SRC_MCP=""
for candidate in "$HOME/.claude.json" "$HOME/.claude/.claude.json"; do
    if [[ -f "$candidate" ]]; then
        if [[ -z "$SRC_MCP" ]] || [[ "$candidate" -nt "$SRC_MCP" ]]; then
            SRC_MCP="$candidate"
        fi
    fi
done
OUT_MCP="$REPO/manifests/claude/mcp.json"

if [[ -f "$SRC_MCP" ]]; then
    # env에 정의된 export 변수 이름 추출. 구분자는 NUL이 아닌 안전한 \x01 (경로/값에 안 나옴)
    SUBSTITUTIONS=""
    SEP=$'\x01'
    if [[ -f "$HOME/.config/agent-dotfiles/env" ]]; then
        while IFS= read -r line; do
            [[ "$line" =~ ^export[[:space:]]+([A-Za-z_][A-Za-z0-9_]*)= ]] || continue
            varname="${BASH_REMATCH[1]}"
            value="${!varname:-}"
            [[ -z "$value" || "$value" == "$HOME" ]] && continue
            SUBSTITUTIONS+="${value}${SEP}{{${varname}}}"$'\n'
        done < "$HOME/.config/agent-dotfiles/env"
    fi

    # 1차: jq로 기본 추출 (치환 X)
    tmp_json=$(mktemp)
    trap 'rm -f "$tmp_json" "$tmp_json.bak"' EXIT
    jq '{
        "$comment": "자동 생성. {{...}} placeholder는 ~/.config/agent-dotfiles/env 변수로 expand됨.",
        servers: [
            (.mcpServers // {}) | to_entries[] | {
                name: .key,
                type: (.value.type // "stdio"),
                scope: "user",
                command: (.value.command // null),
                args: (.value.args // null),
                url: (.value.url // null)
            } | with_entries(select(.value != null))
        ]
    }' "$SRC_MCP" > "$tmp_json"

    # sed 정규식 메타문자 + 구분자(#) 이스케이프
    # BSD/GNU 양쪽 호환되는 단순한 패턴
    sed_escape() {
        printf '%s' "$1" | sed -e 's/[\\\/&]/\\&/g' -e 's/[.*^$]/\\&/g' -e 's/\[/\\[/g' -e 's/\]/\\]/g' -e 's/#/\\#/g'
    }

    # 2차: env 변수 값을 {{VARNAME}}로 역치환 — 긴 경로 먼저
    if [[ -n "$SUBSTITUTIONS" ]]; then
        while IFS="$SEP" read -r value placeholder; do
            [[ -z "$value" ]] && continue
            esc_value=$(sed_escape "$value")
            sed -i.bak "s#${esc_value}#${placeholder}#g" "$tmp_json"
            rm -f "$tmp_json.bak"
        done < <(printf '%s' "$SUBSTITUTIONS" | awk -F"$SEP" 'NF>=2{print length($1)"\t"$0}' | sort -rn | cut -f2-)
    fi

    # 3차: 마지막에 $HOME → {{HOME}}
    esc_home=$(sed_escape "$HOME")
    sed -i.bak "s#${esc_home}#{{HOME}}#g" "$tmp_json"
    rm -f "$tmp_json.bak"

    mv "$tmp_json" "$OUT_MCP"
    n=$(jq '.servers | length' "$OUT_MCP")
    printf '  %s✓%s MCP 서버 (Claude): %d개\n' "$C_OK" "$C_OFF" "$n"
fi

printf '  %sCodex MCP는 ~/.codex/config.toml 안에 있어서 chezmoi re-add로 자동 sync%s\n' "$C_DIM" "$C_OFF"
