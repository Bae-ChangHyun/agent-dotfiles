#!/usr/bin/env bash
# Codex MCP 점검.
# Codex의 MCP는 config.toml 내 [mcp_servers.*] 블록으로 관리되므로
# chezmoi apply가 끝나면 자동 반영. 이 스크립트는 정합성 검증만.
set -euo pipefail

REPO_ROOT="${REPO_ROOT:-$HOME/.local/share/chezmoi}"
MANIFEST="$REPO_ROOT/manifests/codex/mcp.toml"
CONFIG="$HOME/.codex/config.toml"

log() { printf '\033[1;34m[codex/mcp]\033[0m %s\n' "$*"; }

if [[ ! -f "$CONFIG" ]]; then
    log "❌ ~/.codex/config.toml 없음 — chezmoi apply 먼저 실행"
    exit 1
fi

log "Manifest에 선언된 서버:"
grep -E '^\[mcp_servers\.[^.]+\]' "$MANIFEST" 2>/dev/null | sed 's/^/  /' || log "  (manifest에 선언 없음)"

log ""
log "config.toml에 실제 적용된 서버:"
grep -E '^\[mcp_servers\.[^.]+\]' "$CONFIG" | sed 's/^/  /' || log "  (없음)"

# 시크릿 복호화 검증 — chezmoi 템플릿 표기({{ ... }})가 남아있으면 미복호화
log ""
if grep -qE '\{\{[^}]*decrypt[^}]*\}\}' "$CONFIG"; then
    log "❌ 시크릿 미복호화 — '{{ ... decrypt ... }}' 표기가 config.toml에 남아있음"
    log "   → age 마스터 키 확인: ~/.config/chezmoi/key.txt"
    log "   → 다시 적용: chezmoi apply ~/.codex/config.toml"
else
    log "✓ 시크릿 복호화 정상"
fi

log "✓ Codex MCP 점검 완료"
