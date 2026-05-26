#!/usr/bin/env bash
# 공통 바이너리 설치. ~/.local/bin 에 깔아서 sudo 안 쓰게.
set -euo pipefail

BIN="$HOME/.local/bin"
mkdir -p "$BIN"
export PATH="$BIN:$PATH"

# OS / Arch 감지
case "$(uname -s)" in
    Linux*)  OS="linux" ;;
    Darwin*) OS="darwin" ;;
    *)       echo "지원하지 않는 OS: $(uname -s)"; exit 1 ;;
esac
case "$(uname -m)" in
    x86_64|amd64)   ARCH="amd64" ;;
    arm64|aarch64)  ARCH="arm64" ;;
    *)              echo "지원하지 않는 ARCH: $(uname -m)"; exit 1 ;;
esac

log() { printf '\033[1;36m[install-binaries]\033[0m %s\n' "$*"; }
have() { command -v "$1" >/dev/null 2>&1; }
log "감지된 플랫폼: $OS/$ARCH"

# macOS면 Homebrew도 PATH에 — apple silicon 우선
if [[ "$OS" == "darwin" ]]; then
    [[ -d /opt/homebrew/bin ]] && export PATH="/opt/homebrew/bin:$PATH"
    [[ -d /usr/local/bin ]] && export PATH="/usr/local/bin:$PATH"
fi

# chezmoi
if ! have chezmoi; then
    log "chezmoi 설치"
    sh -c "$(curl -fsLS get.chezmoi.io)" -- -b "$BIN"
else
    log "chezmoi ✓ ($(chezmoi --version | head -1))"
fi

# age + age-keygen
if ! have age || ! have age-keygen; then
    log "age 설치 ($OS/$ARCH)"
    if [[ "$OS" == "darwin" ]] && have brew; then
        brew install age
    else
        VER="1.2.1"
        TMP=$(mktemp -d)
        curl -fsSL "https://github.com/FiloSottile/age/releases/download/v${VER}/age-v${VER}-${OS}-${ARCH}.tar.gz" \
            | tar -xz -C "$TMP"
        mv "$TMP/age/age" "$TMP/age/age-keygen" "$BIN/"
        rm -rf "$TMP"
    fi
else
    log "age ✓ ($(age --version))"
fi

# uv (Python)
if ! have uv; then
    log "uv 설치"
    curl -LsSf https://astral.sh/uv/install.sh | sh
else
    log "uv ✓ ($(uv --version))"
fi

# rtk (Rust Token Killer — rtk-ai/rtk 공식)
# brew 또는 최신 release 태그의 install.sh (master HEAD curl pipe sh 지양 — 공급망 공격 위험)
if ! have rtk; then
    log "rtk 설치"
    if [[ "$OS" == "darwin" ]] && have brew; then
        brew install rtk
    else
        # 최신 release 태그를 GitHub API로 조회 후 그 태그의 install.sh 실행 (HEAD 직접 X)
        if have gh; then
            RTK_TAG=$(gh release view -R rtk-ai/rtk --json tagName -q .tagName 2>/dev/null || echo "")
        elif have curl; then
            RTK_TAG=$(curl -fsSL https://api.github.com/repos/rtk-ai/rtk/releases/latest 2>/dev/null | grep -oE '"tag_name":\s*"[^"]+"' | head -1 | sed 's/.*"\(.*\)"/\1/')
        fi
        if [[ -n "${RTK_TAG:-}" ]]; then
            log "  → rtk-ai/rtk@$RTK_TAG install.sh 실행"
            curl -fsSL "https://raw.githubusercontent.com/rtk-ai/rtk/${RTK_TAG}/install.sh" | sh
        else
            log "  ⚠ 최신 release 태그 조회 실패 — rtk 수동 설치 안내: https://github.com/rtk-ai/rtk/releases"
        fi
    fi
else
    log "rtk ✓ ($(rtk --version))"
fi

# gh (GitHub CLI) — apt 또는 brew 필요
if ! have gh; then
    log "gh 미설치 — 'sudo apt install gh' 또는 https://cli.github.com 참고"
else
    log "gh ✓"
fi

# Claude Code CLI
if ! have claude; then
    log "claude (Claude Code CLI) 미설치 — https://claude.ai/code 안내 따라 설치"
else
    log "claude ✓ ($(claude --version 2>&1 | head -1))"
fi

# Codex CLI
if ! have codex; then
    log "codex 미설치 — https://github.com/openai/codex 안내 따라 설치"
else
    log "codex ✓"
fi

log "공통 바이너리 점검 완료"
