#!/usr/bin/env bash
# Codex MCP 점검 + 경로 검증.
# Codex의 MCP는 config.toml 내 [mcp_servers.*] 블록으로 관리. chezmoi apply가 자동 반영.
# 이 스크립트는 (1) 시크릿 복호화 (2) stdio 서버의 command 경로가 이 PC에 있는지 검증.
set -euo pipefail

REPO_ROOT="${REPO_ROOT:-$HOME/.local/share/chezmoi}"
CONFIG="$HOME/.codex/config.toml"

C_OK=$(tput setaf 2 2>/dev/null || echo "")
C_WARN=$(tput setaf 3 2>/dev/null || echo "")
C_DIM=$(tput setaf 8 2>/dev/null || echo "")
C_OFF=$(tput sgr0 2>/dev/null || echo "")

log() { printf '\033[1;34m[codex/mcp]\033[0m %s\n' "$*"; }

if [[ ! -f "$CONFIG" ]]; then
    log "❌ ~/.codex/config.toml 없음 — chezmoi apply 먼저 실행"
    exit 1
fi

# 등록된 서버 출력
log "config.toml에 적용된 MCP 서버:"
grep -E '^\[mcp_servers\.[^.]+\]' "$CONFIG" | sed 's/^/  /' || log "  (없음)"

# 시크릿 복호화 검증
if grep -qE '\{\{[^}]*decrypt[^}]*\}\}' "$CONFIG"; then
    printf '  %s⚠%s 시크릿 미복호화 — chezmoi apply 다시 실행 필요\n' "$C_WARN" "$C_OFF"
else
    printf '  %s✓%s 시크릿 복호화 정상\n' "$C_OK" "$C_OFF"
fi

# stdio 서버의 command 경로 검증 (절대경로만)
# config.toml의 stdio 정의 예:
#   [mcp_servers.foo]
#   command = "/path/to/bin"
#   args = ["..."]
log "stdio command 경로 검증:"
missing=0
while IFS= read -r cmd_line; do
    # command = "..." 추출
    cmd_val=$(echo "$cmd_line" | sed -E 's/^command[[:space:]]*=[[:space:]]*"(.*)"[[:space:]]*$/\1/')
    [[ -z "$cmd_val" || "$cmd_val" == "$cmd_line" ]] && continue
    # 절대경로만 검증 (PATH 명령은 검사 안 함 — PATH 보강은 dsync 책임)
    if [[ "$cmd_val" == /* ]] || [[ "$cmd_val" == "$HOME"/* ]]; then
        if [[ ! -x "$cmd_val" ]]; then
            printf '  %s⚠%s command 경로 없음/실행불가: %s\n' "$C_WARN" "$C_OFF" "$cmd_val"
            missing=$((missing+1))
        fi
    fi
done < <(grep -E '^command[[:space:]]*=' "$CONFIG" || true)

if [[ $missing -eq 0 ]]; then
    printf '  %s✓%s 모든 stdio command 경로 OK\n' "$C_OK" "$C_OFF"
else
    printf '  %s%d개 경로 문제 — 해당 도구 설치/경로 수정 필요%s\n' "$C_DIM" "$missing" "$C_OFF"
fi

log "✓ Codex MCP 점검 완료"
