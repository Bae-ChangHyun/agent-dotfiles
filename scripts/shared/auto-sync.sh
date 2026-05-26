#!/usr/bin/env bash
# dotfiles 양방향 자동 sync.
# Usage:
#   auto-sync.sh push   # 홈 → dotfiles → git push
#   auto-sync.sh pull   # git pull → 홈에 apply
#   auto-sync.sh both   # pull → push
#
# Cron 예시:
#   매시간 push, 매일 새벽 pull:
#   0 * * * *  $HOME/.local/share/chezmoi/scripts/shared/auto-sync.sh push >> /tmp/dotfiles-sync.log 2>&1
#   30 5 * * * $HOME/.local/share/chezmoi/scripts/shared/auto-sync.sh pull >> /tmp/dotfiles-sync.log 2>&1
set -euo pipefail

REPO="$HOME/.local/share/chezmoi"
MODE="${1:-both}"
HOSTNAME_SHORT="$(hostname -s)"
TS=$(date +%F-%H%M)

cd "$REPO"

log() { printf '[%s][%s] %s\n' "$TS" "$HOSTNAME_SHORT" "$*"; }

pull_step() {
    log "1) pull from origin"
    if ! git pull --ff-only 2>&1; then
        log "⚠ ff-only pull 실패 — 수동 merge 필요"
        return 1
    fi
    log "2) chezmoi apply (텍스트 파일/스킬/메모리)"
    CHEZMOI_SKIP_BOOTSTRAP=1 chezmoi apply --force

    log "3) 홈 cleanup (dotfiles에 없는데 홈에 있는 본인 폴더 삭제)"
    # 양방향 삭제 sync: 다른 PC에서 지운 스킬/팀이 이 PC 홈에 남아있으면 삭제
    for base in dot_claude/skills dot_codex/skills dot_claude/teams; do
        home_base="$HOME/.${base#dot_}"
        [[ -d "$home_base" ]] || continue
        for home_item in "$home_base"/*/; do
            [[ -d "$home_item" ]] || continue
            name=$(basename "${home_item%/}")
            [[ -L "${home_item%/}" ]] && continue                      # symlink: 외부 마켓
            [[ "$name" == .system || "$name" == codex-primary-runtime ]] && continue
            src_item="$REPO/$base/$name"
            if [[ ! -d "$src_item" ]]; then
                log "  🗑️  $home_item (dotfiles에 없음)"
                rm -rf "$home_item"
            fi
        done
    done

    log "4) 플러그인/마켓 동기화 (manifest와 일치하도록 install/uninstall)"
    if command -v claude >/dev/null 2>&1; then
        bash "$REPO/scripts/claude/install-plugins.sh" || true
    else
        log "  ⊘ claude CLI 없음 → skip (PATH에 claude 추가 필요)"
    fi
}

push_step() {
    # 다른 PC가 추가한 변경 먼저 받기 (안 받으면 자동 삭제가 위험)
    log "0) git pull 먼저 (다른 PC 변경 받기)"
    git pull --ff-only 2>&1 | sed 's/^/  /' || { log "⚠ pull 실패 — 수동 merge 필요"; return 1; }

    log "1) manifest sync (플러그인/마켓/MCP 자동 탐지)"
    bash "$REPO/scripts/shared/sync-manifests.sh"

    log "2) 홈에서 삭제된 스킬/팀 자동 forget (양쪽 sync 삭제)"
    # dotfiles에 있는데 홈에 없는 항목 = 사용자가 홈에서 지운 거 → forget
    for base in dot_claude/skills dot_codex/skills dot_claude/teams; do
        [[ -d "$REPO/$base" ]] || continue
        for src_item in "$REPO/$base"/*/; do
            [[ -d "$src_item" ]] || continue
            name=$(basename "${src_item%/}")
            # symlink_ / dot_system 같은 ignore 대상 skip
            [[ "$name" == symlink_* || "$name" == "dot_system" || "$name" == ".system" ]] && continue
            home_item="$HOME/.${base#dot_}/$name"
            if [[ ! -d "$home_item" ]]; then
                log "  🗑️  forget: $name (홈에 없음)"
                chezmoi forget --force "$home_item" 2>&1 | sed 's/^/    /' || true
            fi
        done
    done

    log "3) 새 스킬/팀 자동 add (chezmoi에 없는 항목 탐지)"
    # ~/.claude/skills/* 와 ~/.codex/skills/* 중 chezmoi가 모르는 폴더만 골라서 add
    # 주의: 기존 .tmpl 파일이 있는 디렉토리는 건드리지 않음 (chezmoi add가 .md로 강등시킴)
    for base in "$HOME/.claude/skills" "$HOME/.codex/skills" "$HOME/.claude/teams"; do
        [[ -d "$base" ]] || continue
        for item in "$base"/*/; do
            [[ -d "$item" ]] || continue
            name=$(basename "${item%/}")
            # symlink는 외부 마켓플레이스 스킬이라 skip
            [[ -L "${item%/}" ]] && continue
            # Codex 시스템 스킬 skip
            [[ "$name" == ".system" || "$name" == "codex-primary-runtime" ]] && continue
            # 이미 추적 중인지 검사 (output 비어있으면 = managed 아님)
            if [[ -z "$(chezmoi managed "${item%/}" 2>/dev/null)" ]]; then
                # ★ 이 폴더 내에 .tmpl이 이미 chezmoi 안에 있으면 skip (강등 방지)
                src_dir="$REPO/dot_${base#$HOME/.}/$name"
                src_dir="${src_dir//\/\///}"
                if compgen -G "$src_dir/*.tmpl" > /dev/null 2>&1; then
                    log "  ⊘ $name — 기존 .tmpl 존재, skip"
                    continue
                fi
                log "  + 새 항목 add: ${item%/}"
                chezmoi add "${item%/}" 2>&1 | sed 's/^/    /' || true
            fi
        done
    done

    log "4) chezmoi re-add (기존 추적 파일 갱신)"
    chezmoi re-add 2>/dev/null || true

    if [[ -z "$(git status --porcelain)" ]]; then
        log "변경 없음 — push 안 함"
        return 0
    fi
    log "5) commit + push"
    git add -A
    git commit -m "🔄 autosync from ${HOSTNAME_SHORT} ${TS}"
    git push
}

case "$MODE" in
    pull)   pull_step ;;
    push)   push_step ;;
    both)   pull_step && push_step ;;
    diff)   chezmoi diff ;;
    cd)     cd "$REPO" && exec "${SHELL:-bash}" ;;
    status)
        log "branch:   $(git branch --show-current)"
        log "ahead:    $(git rev-list --count @{u}..HEAD 2>/dev/null || echo 0) 개 commit (push 필요)"
        log "behind:   $(git rev-list --count HEAD..@{u} 2>/dev/null || echo 0) 개 commit (pull 필요)"
        log "diff:     $(chezmoi diff 2>/dev/null | wc -l) lines (홈 vs dotfiles)"
        ;;
    rm|remove)
        target="${2:-}"
        if [[ -z "$target" ]]; then
            echo "Usage: dsync rm <path>"
            echo "  예: dsync rm ~/.claude/skills/old-skill"
            echo "  예: dsync rm ~/.codex/skills/foo"
            exit 1
        fi
        # 절대경로 보정
        [[ "$target" != /* ]] && target="$PWD/$target"
        log "삭제: $target (홈 + dotfiles 양쪽)"
        chezmoi forget --force "$target" 2>&1 | sed 's/^/  /' || true
        rm -rf "$target"
        log "commit + push"
        cd "$REPO"
        git add -A
        if [[ -z "$(git status --porcelain)" ]]; then
            log "변경 없음"; exit 0
        fi
        git commit -m "🗑️  remove $(basename "$target") from ${HOSTNAME_SHORT}"
        git push
        log "✓ 완료. 다른 PC에서 'dsync pull' 후, 홈에 남아있으면 'rm -rf $target' 직접 실행"
        ;;
    *)
        cat <<EOF
Usage: dsync [command]
  push        (기본) 홈 → dotfiles → GitHub
  pull        GitHub → 홈
  both        pull + push
  diff        변경 미리보기
  rm <path>   스킬/파일 삭제 (홈 + dotfiles 양쪽)
  cd          repo로 이동 후 새 셸
  status      현재 상태 요약
EOF
        exit 1
        ;;
esac
