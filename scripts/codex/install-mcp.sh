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
grep -E '^\[mcp_servers\.[^.]+\]' "$MANIFEST" | sed 's/^/  /'

log ""
log "config.toml에 실제 적용된 서버:"
grep -E '^\[mcp_servers\.[^.]+\]' "$CONFIG" | sed 's/^/  /'

# refero 토큰 검증
log ""
if grep -q 'Bearer mcp-' "$CONFIG"; then
    log "✓ refero Bearer 토큰 복호화 성공"
else
    log "❌ refero 토큰 미적용. 'chezmoi apply ~/.codex/config.toml' 다시 시도"
fi

log "✓ Codex MCP 점검 완료"
