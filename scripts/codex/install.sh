#!/usr/bin/env bash
# Codex 영역 단독 설치.
# Codex는 MCP 서버가 config.toml 안에 들어가 있어서 chezmoi apply 만으로 거의 끝남.
set -euo pipefail

REPO_ROOT="${REPO_ROOT:-$HOME/.local/share/chezmoi}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

log() { printf '\033[1;34m[codex]\033[0m %s\n' "$*"; }

log "1/2 chezmoi apply (dot_codex 영역) — config.toml.tmpl 안의 시크릿 자동 복호화"
chezmoi apply --include=files --source-path="$REPO_ROOT/dot_codex" 2>&1 \
    || chezmoi apply ~/.codex

log "2/2 MCP 점검"
bash "$SCRIPT_DIR/install-mcp.sh"

log "✓ Codex 셋업 완료. 'codex' 실행해서 확인"
