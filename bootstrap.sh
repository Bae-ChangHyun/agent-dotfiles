#!/usr/bin/env bash
# agent-dotfiles 인터랙티브 부트스트랩
#
# Usage:
#   ./bootstrap.sh              # 인터랙티브 (각 단계마다 y/n)
#   ./bootstrap.sh --all-yes    # 묻지 않고 전부 실행
#   ./bootstrap.sh --dry-run    # 실행 안 하고 무슨 일 일어날지만 출력
#   ./bootstrap.sh --claude     # Claude 영역만
#   ./bootstrap.sh --codex      # Codex 영역만
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ALL_YES=0
DRY_RUN=0
ONLY_CLAUDE=0
ONLY_CODEX=0

for arg in "$@"; do
    case "$arg" in
        --all-yes|-y) ALL_YES=1 ;;
        --dry-run|-n) DRY_RUN=1 ;;
        --claude) ONLY_CLAUDE=1 ;;
        --codex) ONLY_CODEX=1 ;;
        --help|-h)
            sed -n '3,12p' "$0"
            exit 0
            ;;
        *) echo "알 수 없는 옵션: $arg"; exit 1 ;;
    esac
done

# 색상
C_HEAD=$(tput setaf 6 2>/dev/null || echo "")
C_STEP=$(tput setaf 3 2>/dev/null || echo "")
C_OK=$(tput setaf 2 2>/dev/null || echo "")
C_SKIP=$(tput setaf 8 2>/dev/null || echo "")
C_OFF=$(tput sgr0 2>/dev/null || echo "")

ask() {
    local prompt="$1"
    [[ $ALL_YES -eq 1 ]] && { echo "${C_OK}auto-yes${C_OFF}"; return 0; }
    read -r -p "$prompt [Y/n]: " r </dev/tty
    [[ -z "$r" || "$r" =~ ^[Yy]$ ]]
}

run() {
    local desc="$1"; shift
    if [[ $DRY_RUN -eq 1 ]]; then
        echo "  ${C_SKIP}DRY-RUN ▶${C_OFF} $*"
        return 0
    fi
    "$@"
}

step() {
    local num="$1" total="$2" title="$3"
    echo
    echo "${C_HEAD}[$num/$total]${C_OFF} ${C_STEP}$title${C_OFF}"
}

# ====================================================================
echo "${C_HEAD}╔════════════════════════════════════════════════╗${C_OFF}"
echo "${C_HEAD}║  agent-dotfiles 온보딩                          ║${C_OFF}"
echo "${C_HEAD}╚════════════════════════════════════════════════╝${C_OFF}"
echo
echo "  repo: $REPO_ROOT"
[[ $DRY_RUN -eq 1 ]] && echo "  ${C_SKIP}MODE: DRY-RUN${C_OFF}"
[[ $ALL_YES -eq 1 ]] && echo "  ${C_SKIP}MODE: ALL-YES${C_OFF}"
[[ $ONLY_CLAUDE -eq 1 ]] && echo "  ${C_SKIP}SCOPE: CLAUDE only${C_OFF}"
[[ $ONLY_CODEX -eq 1 ]] && echo "  ${C_SKIP}SCOPE: CODEX only${C_OFF}"

TOTAL=8
N=1

# ---- 1. 공통 바이너리 ----
if [[ $ONLY_CLAUDE -eq 0 && $ONLY_CODEX -eq 0 ]]; then
    step $N $TOTAL "공통 바이너리 (chezmoi, age, uv, rtk 등)"
    if ask "  설치/점검할까요?"; then
        run "binaries" bash "$REPO_ROOT/scripts/shared/install-binaries.sh"
    else echo "  ${C_SKIP}건너뜀${C_OFF}"; fi
fi
((N++))

# ---- 2. 마스터 키 확인 ----
step $N $TOTAL "age 마스터 키 확인 (시크릿 복호화에 필요)"
if [[ -f "$HOME/.config/chezmoi/key.txt" ]]; then
    echo "  ${C_OK}✓ 마스터 키 발견${C_OFF}"
else
    echo "  ${C_SKIP}⚠ ~/.config/chezmoi/key.txt 없음. docs/SECRETS.md 참고하여 키를 가져와야 합니다.${C_OFF}"
    if ask "  지금 새로 생성할까요? (기존 시크릿 복호화 불가능해짐)"; then
        run "keygen" age-keygen -o "$HOME/.config/chezmoi/key.txt"
        run "chmod" chmod 600 "$HOME/.config/chezmoi/key.txt"
    fi
fi
((N++))

# ---- 3. chezmoi apply (Claude) ----
if [[ $ONLY_CODEX -eq 0 ]]; then
    step $N $TOTAL "Claude Code 설정 적용 (CLAUDE.md, settings.json, skills, hooks, memory)"
    if [[ -n "${CHEZMOI:-}" ]]; then
        echo "  ${C_OK}✓ chezmoi run 안 — 이미 적용됨, skip${C_OFF}"
    elif ask "  ~/.claude/ 에 dot_claude/ 적용?"; then
        run "claude-apply" chezmoi apply ~/.claude
    else echo "  ${C_SKIP}건너뜀${C_OFF}"; fi
fi
((N++))

# ---- 4. Claude 플러그인 + 마켓플레이스 ----
if [[ $ONLY_CODEX -eq 0 ]]; then
    step $N $TOTAL "Claude 마켓플레이스 등록 + 플러그인 설치"
    if ask "  manifests/claude/* 기반으로 설치?"; then
        run "claude-plugins" bash "$REPO_ROOT/scripts/claude/install-plugins.sh"
    else echo "  ${C_SKIP}건너뜀${C_OFF}"; fi
fi
((N++))

# ---- 5. Claude MCP ----
if [[ $ONLY_CODEX -eq 0 ]]; then
    step $N $TOTAL "Claude MCP 서버 등록 (manifests/claude/mcp.json 기반)"
    if ask "  manifests/claude/mcp.json 기반으로 등록?"; then
        run "claude-mcp" bash "$REPO_ROOT/scripts/claude/install-mcp.sh"
    else echo "  ${C_SKIP}건너뜀${C_OFF}"; fi
fi
((N++))

# ---- 6. Codex apply ----
if [[ $ONLY_CLAUDE -eq 0 ]]; then
    step $N $TOTAL "Codex 설정 적용 (AGENTS.md, config.toml, skills) — 시크릿 자동 복호화"
    if [[ -n "${CHEZMOI:-}" ]]; then
        echo "  ${C_OK}✓ chezmoi run 안 — 이미 적용됨, skip${C_OFF}"
    elif ask "  ~/.codex/ 에 dot_codex/ 적용?"; then
        run "codex-apply" chezmoi apply ~/.codex
    else echo "  ${C_SKIP}건너뜀${C_OFF}"; fi
fi
((N++))

# ---- 7. Codex MCP 점검 ----
if [[ $ONLY_CLAUDE -eq 0 ]]; then
    step $N $TOTAL "Codex MCP 정합성 점검"
    if ask "  적용된 config.toml 확인?"; then
        run "codex-mcp" bash "$REPO_ROOT/scripts/codex/install-mcp.sh"
    else echo "  ${C_SKIP}건너뜀${C_OFF}"; fi
fi
((N++))

# ---- 8. 개인 프로젝트 clone ----
if [[ $ONLY_CLAUDE -eq 0 && $ONLY_CODEX -eq 0 ]]; then
    step $N $TOTAL "개인 프로젝트 clone (manifests/personal-projects.json 기반)"
    if ask "  manifests/personal-projects.json 기반으로 clone + setup?"; then
        run "clone" bash "$REPO_ROOT/scripts/shared/clone-personal-projects.sh"
    else echo "  ${C_SKIP}건너뜀${C_OFF}"; fi
fi

# ====================================================================
echo
echo "${C_HEAD}╔════════════════════════════════════════════════╗${C_OFF}"
echo "${C_HEAD}║  ✓ 부트스트랩 완료${C_OFF}"
echo "${C_HEAD}╚════════════════════════════════════════════════╝${C_OFF}"
echo
echo "다음 할 일:"
echo "  • ${C_STEP}claude${C_OFF} 실행해서 Claude Code 동작 확인"
echo "  • ${C_STEP}codex${C_OFF} 실행해서 Codex 동작 확인"
echo "  • 머신별 경로/시크릿 mismatch 경고 시 ~/.config/agent-dotfiles/env 에 변수 정의"
echo "  • 새 시크릿 추가/회전은 docs/SECRETS.md 참고"
