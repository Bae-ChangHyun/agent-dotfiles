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

# stdio MCP의 경로 존재 검증 — args 안에 절대경로 토큰 + 미해결 placeholder 모두 catch
verify_paths() {
    local args_json="$1"
    local missing=""
    while IFS= read -r token; do
        [[ -z "$token" ]] && continue
        # 미해결 placeholder ({{VARNAME}}가 남아있음 = env에 정의 안 됨)
        if [[ "$token" == *'{{'*'}}'* ]]; then
            missing+="$token  (미해결 placeholder — env에 변수 정의 필요)"$'\n'
            continue
        fi
        # 절대경로 / 홈 시작인데 실제 파일 없음
        if [[ "$token" == /* || "$token" == "$HOME"/* ]]; then
            if [[ ! -e "$token" ]]; then
                missing+="$token"$'\n'
            fi
        fi
    done < <(echo "$args_json" | jq -r '.[]?' 2>/dev/null | while read -r t; do expand_path "$t"; done)
    printf '%s' "$missing"
}

count=$(jq '.servers | length' "$MCP_JSON")
[[ "$count" == "0" ]] && { printf '  %s✓%s MCP 서버 manifest 비어있음 — skip\n' "$C_OK" "$C_OFF"; exit 0; }

# 현재 등록된 MCP 서버 목록
HAVE_MCP=$(claude mcp list 2>/dev/null | awk '/^[a-zA-Z0-9_-]+/{print $1}' | sort -u || true)

# counter 변수 제거 (pipe subshell)
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
            # 각 arg를 expand_path로 치환 — 배열로 보관 (공백 포함 경로 안전)
            args_arr=()
            while IFS= read -r token; do
                args_arr+=("$(expand_path "$token")")
            done < <(echo "$args_json" | jq -r '.[]?' 2>/dev/null)

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
                printf '  %s⚠%s %s — 의존 경로가 이 PC에 없음:\n' "$C_WARN" "$C_OFF" "$name"
                printf '%s' "$missing" | sed "s|^|    ${C_WARN}- ${C_OFF}|"

                # missing 안에 "미해결 placeholder" 표시가 있으면 → env 정의 안내
                # 없으면 → 경로 자체 미생성이므로 폴더/manifest 수정 안내
                if [[ "$missing" == *'미해결 placeholder'* ]]; then
                    unresolved=$(printf '%s' "$missing" | grep -oE '\{\{[A-Za-z_][A-Za-z0-9_]*\}\}' | sort -u)
                    printf '    %s→ ~/.config/agent-dotfiles/env 에 다음 변수 정의 필요:%s\n' "$C_DIM" "$C_OFF"
                    for ph in $unresolved; do
                        varname="${ph//[\{\}]/}"
                        printf '       %sexport %s="/your/path"%s\n' "$C_DIM" "$varname" "$C_OFF"
                    done
                else
                    printf '    %s→ 해결: (a) 해당 폴더 생성/symlink (b) 이 MCP 미사용시 무시%s\n' "$C_DIM" "$C_OFF"
                fi
                continue
            fi

            printf '  %s+%s %s (stdio): %s %s\n' "$C_ADD" "$C_OFF" "$name" "$command" "${args_arr[*]}"
            claude mcp add "$name" --scope "$scope" -- "$command" "${args_arr[@]}" >/dev/null 2>&1 || \
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
