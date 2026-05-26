#!/usr/bin/env bash
# Claude Code MCP 서버를 manifest와 동기화.
# stdio 서버의 경로 의존성을 사전 검증, 경로 없으면 경고+skip.
set -euo pipefail

REPO_ROOT="${REPO_ROOT:-$HOME/.local/share/chezmoi}"
MCP_JSON="$REPO_ROOT/manifests/claude/mcp.json"

C_OK=$(tput setaf 2 2>/dev/null || echo "")
C_ADD=$(tput setaf 2 2>/dev/null || echo "")
C_WARN=$(tput setaf 3 2>/dev/null || echo "")
C_RM=$(tput setaf 1 2>/dev/null || echo "")
C_DIM=$(tput setaf 8 2>/dev/null || echo "")
C_OFF=$(tput sgr0 2>/dev/null || echo "")

if ! command -v claude >/dev/null 2>&1; then
    printf '  %s⊘%s claude CLI 없음 → MCP sync skip\n' "$C_DIM" "$C_OFF"
    exit 0
fi
command -v jq >/dev/null 2>&1 || { echo "  ✗ jq 필요"; exit 1; }
[[ -f "$MCP_JSON" ]] || { printf '  %s⊘%s mcp.json 없음 → skip\n' "$C_DIM" "$C_OFF"; exit 0; }

# 머신별 env source (선택). {{VARNAME}} placeholder는 env의 그 변수 값으로 expand.
[[ -f "$HOME/.config/agent-dotfiles/env" ]] && source "$HOME/.config/agent-dotfiles/env" || true

expand_path() {
    local p="$1"
    p="${p//\{\{HOME\}\}/$HOME}"
    # env에 정의된 변수 그대로 expand (사용자가 어떤 변수명 쓰든 OK)
    if [[ -f "$HOME/.config/agent-dotfiles/env" ]]; then
        while IFS= read -r line; do
            [[ "$line" =~ ^export[[:space:]]+([A-Za-z_][A-Za-z0-9_]*)= ]] || continue
            local varname="${BASH_REMATCH[1]}"
            local value="${!varname:-}"
            [[ -z "$value" ]] && continue
            p="${p//\{\{$varname\}\}/$value}"
        done < "$HOME/.config/agent-dotfiles/env"
    fi
    echo "$p"
}

# stdio MCP의 경로 존재 검증 — args 안에 디렉토리/파일 경로 의심되는 토큰 검사
verify_paths() {
    local args_json="$1"
    local missing=""
    # args 배열의 각 원소 중 / 로 시작하거나 ~/로 시작하는 것 (경로 의심)
    while IFS= read -r token; do
        [[ -z "$token" ]] && continue
        # 절대경로 또는 홈 시작
        if [[ "$token" == /* || "$token" == "$HOME"/* ]]; then
            if [[ ! -e "$token" ]]; then
                missing+="$token\n"
            fi
        fi
    done < <(echo "$args_json" | jq -r '.[]?' 2>/dev/null | while read -r t; do echo "$(expand_path "$t")"; done)
    echo -ne "$missing"
}

count=$(jq '.servers | length' "$MCP_JSON")
[[ "$count" == "0" ]] && { printf '  %s✓%s MCP 서버 manifest 비어있음 — skip\n' "$C_OK" "$C_OFF"; exit 0; }

# 현재 등록된 MCP 서버 목록
HAVE_MCP=$(claude mcp list 2>/dev/null | awk '/^[a-zA-Z0-9_-]+/{print $1}' | sort -u || true)

added=0; warned=0; skipped=0
jq -c '.servers[]' "$MCP_JSON" | while read -r srv; do
    name=$(echo "$srv" | jq -r '.name')
    type=$(echo "$srv" | jq -r '.type // "stdio"')
    scope=$(echo "$srv" | jq -r '.scope // "user"')

    # 이미 등록됐으면 skip (또는 verify만)
    if grep -qxF "$name" <<< "$HAVE_MCP"; then
        printf '  %s=%s %s (이미 등록됨)\n' "$C_DIM" "$C_OFF" "$name"
        continue
    fi

    case "$type" in
        stdio)
            command=$(echo "$srv" | jq -r '.command')
            command=$(expand_path "$command")
            args_json=$(echo "$srv" | jq '.args // []')
            args=$(echo "$args_json" | jq -r --arg home "$HOME" --arg pr "$PROJECTS_ROOT" --arg ov "$OBSIDIAN_SYNC" \
                'map(gsub("\\{\\{HOME\\}\\}"; $home) | gsub("\\{\\{PROJECTS_ROOT\\}\\}"; $pr) | gsub("\\{\\{OBSIDIAN_VAULT\\}\\}"; $ov)) | join(" ")')

            # 1) command 자체 존재? (절대경로 또는 PATH)
            if [[ "$command" == /* || "$command" == "$HOME"/* ]]; then
                if [[ ! -x "$command" ]]; then
                    printf '  %s⚠%s %s — command 경로 없음: %s\n' "$C_WARN" "$C_OFF" "$name" "$command"
                    printf '    %s→ 이 PC에 해당 바이너리/앱 설치 필요. skip%s\n' "$C_DIM" "$C_OFF"
                    continue
                fi
            elif ! command -v "$command" >/dev/null 2>&1; then
                printf '  %s⚠%s %s — command "%s" PATH에서 못 찾음\n' "$C_WARN" "$C_OFF" "$name" "$command"
                printf '    %s→ 해당 CLI 설치 후 PATH에 추가. skip%s\n' "$C_DIM" "$C_OFF"
                continue
            fi

            # 2) args 안의 절대경로 검증
            missing=$(verify_paths "$args_json")
            if [[ -n "$missing" ]]; then
                # 원본 args에 {{VAR}} placeholder 있었나 확인 (있으면 env 미정의 가능성)
                placeholders=$(echo "$args_json" | jq -r '.[]?' 2>/dev/null | grep -oE '\{\{[A-Z_]+\}\}' | sort -u | tr '\n' ' ')

                printf '  %s⚠%s %s — 의존 경로가 이 PC에 없음:\n' "$C_WARN" "$C_OFF" "$name"
                echo -e "$missing" | sed "s|^|    ${C_WARN}- ${C_OFF}|"

                if [[ -n "$placeholders" ]]; then
                    printf '    %s→ 해결 방법 중 택1:%s\n' "$C_DIM" "$C_OFF"
                    printf '      %s(a) ~/.config/agent-dotfiles/env 에 변수 정의:%s\n' "$C_DIM" "$C_OFF"
                    for ph in $placeholders; do
                        varname="${ph//[\{\}]/}"
                        printf '          %sexport %s="/your/path"%s\n' "$C_DIM" "$varname" "$C_OFF"
                    done
                    printf '      %s(b) 해당 경로에 폴더/심볼릭링크 생성%s\n' "$C_DIM" "$C_OFF"
                    printf '      %s(c) 이 PC에서 이 MCP 안 쓰면 무시%s\n' "$C_DIM" "$C_OFF"
                else
                    printf '    %s→ 해결: (a) 폴더 만들기 (b) manifest를 이 PC 경로로 수정%s\n' "$C_DIM" "$C_OFF"
                fi
                continue
            fi

            printf '  %s+%s %s (stdio): %s %s\n' "$C_ADD" "$C_OFF" "$name" "$command" "$args"
            claude mcp add "$name" --scope "$scope" -- $command $args >/dev/null 2>&1 || \
                printf '    %s(등록 실패)%s\n' "$C_DIM" "$C_OFF"
            ;;
        http|sse)
            url=$(echo "$srv" | jq -r '.url')
            if [[ -z "$url" || "$url" == "null" || "$url" == TODO:* ]]; then
                printf '  %s⊘%s %s — URL 미설정\n' "$C_DIM" "$C_OFF" "$name"
                continue
            fi
            printf '  %s+%s %s (%s): %s\n' "$C_ADD" "$C_OFF" "$name" "$type" "$url"
            claude mcp add "$name" --scope "$scope" --transport "$type" "$url" >/dev/null 2>&1 || \
                printf '    %s(등록 실패)%s\n' "$C_DIM" "$C_OFF"
            ;;
        *)
            printf '  %s?%s %s — 알 수 없는 type: %s\n' "$C_DIM" "$C_OFF" "$name" "$type"
            ;;
    esac
done

printf '  %s✓%s MCP sync 완료\n' "$C_OK" "$C_OFF"
