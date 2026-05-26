#!/usr/bin/env bash
# Claude Code 영역 단독 설치 — 다른 부분 없이 Claude만 셋업하고 싶을 때.
# 순서: chezmoi apply (dot_claude만) → 플러그인 → MCP
set -euo pipefail

REPO_ROOT="${REPO_ROOT:-$HOME/.local/share/chezmoi}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

log() { printf '\033[1;34m[claude]\033[0m %s\n' "$*"; }

log "1/3 chezmoi apply (dot_claude 영역)"
chezmoi apply --include=files --source-path="$REPO_ROOT/dot_claude" 2>&1 \
    || chezmoi apply ~/.claude  # fallback

log "2/3 플러그인 + 마켓플레이스"
bash "$SCRIPT_DIR/install-plugins.sh"

log "3/3 MCP 서버"
bash "$SCRIPT_DIR/install-mcp.sh"

log "✓ Claude Code 셋업 완료. 'claude' 실행해서 확인"
