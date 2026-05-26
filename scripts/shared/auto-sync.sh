#!/usr/bin/env bash
# dsync — Claude Code + Codex 양방향 자동 sync.
set -euo pipefail

# PATH 보강 (cron/SSH 자동화 환경에서도 brew/nvm 등 잡히도록)
# nvm: 설치된 모든 node 버전 bin을 prepend (claude가 있는 버전 잡히도록)
if [[ -d "$HOME/.nvm/versions/node" ]]; then
    for nvm_bin in "$HOME"/.nvm/versions/node/*/bin; do
        [[ -d "$nvm_bin" ]] && export PATH="$nvm_bin:$PATH"
    done
fi
[[ -d /opt/homebrew/bin   ]] && export PATH="/opt/homebrew/bin:$PATH"
[[ -d /usr/local/bin      ]] && export PATH="/usr/local/bin:$PATH"
[[ -d "$HOME/.local/bin"  ]] && export PATH="$HOME/.local/bin:$PATH"

# 머신별 환경변수 파일 (선택). 있으면 source, 없어도 진행.
# 사용자가 자기 스킬/MCP의 placeholder에 맞게 직접 작성.
# 예: echo 'export FOO=/my/path' > ~/.config/agent-dotfiles/env
ENV_FILE="$HOME/.config/agent-dotfiles/env"
[[ -f "$ENV_FILE" ]] && source "$ENV_FILE"

REPO="$HOME/.local/share/chezmoi"
MODE="${1:-push}"
HOSTNAME_SHORT="$(hostname -s)"
TS=$(date +%F-%H%M)

cd "$REPO"

# 동시 실행 방어 (cron + 수동 실행 충돌 방지)
# push/pull/both 같이 git 변경 발생하는 모드만 lock
# flock (Linux util-linux) 우선, 없으면 mkdir 원자적 락 (macOS BSD 호환)
case "$MODE" in
    push|pull|both|rm|remove)
        LOCK_DIR="${TMPDIR:-/tmp}/dsync-$(id -u).lockdir"
        if command -v flock >/dev/null 2>&1; then
            LOCK_FILE="${TMPDIR:-/tmp}/dsync-$(id -u).lock"
            exec 9>"$LOCK_FILE"
            flock -n 9 || { echo "⚠ 다른 dsync 실행 중 — skip"; exit 0; }
            # process exit 시 fd 9 자동 close → lock 해제. 파일은 남지만 0 bytes, 무해.
        else
            # macOS fallback: mkdir 원자적 lock
            if ! mkdir "$LOCK_DIR" 2>/dev/null; then
                echo "⚠ 다른 dsync 실행 중 ($LOCK_DIR) — skip"
                exit 0
            fi
            trap 'rmdir "$LOCK_DIR" 2>/dev/null || true' EXIT
        fi
        ;;
esac

# 색상
B=$(tput bold 2>/dev/null || echo "")
C_HEAD=$(tput setaf 6 2>/dev/null || echo "")
C_OK=$(tput setaf 2 2>/dev/null || echo "")
C_WARN=$(tput setaf 3 2>/dev/null || echo "")
C_ERR=$(tput setaf 1 2>/dev/null || echo "")
C_DIM=$(tput setaf 8 2>/dev/null || echo "")
C_OFF=$(tput sgr0 2>/dev/null || echo "")

section() {
    local emoji="$1" title="$2"
    echo
    printf '%s%s━━━ %s %s%s%s\n' "$B" "$C_HEAD" "$emoji" "$title" "$C_OFF" ""
}
ok()   { printf '  %s✓%s %s\n' "$C_OK"   "$C_OFF" "$*"; }
warn() { printf '  %s⚠%s %s\n' "$C_WARN" "$C_OFF" "$*"; }
err()  { printf '  %s✗%s %s\n' "$C_ERR"  "$C_OFF" "$*"; }
add()  { printf '  %s+%s %s\n' "$C_OK"   "$C_OFF" "$*"; }
rm_()  { printf '  %s-%s %s\n' "$C_ERR"  "$C_OFF" "$*"; }
dim()  { printf '    %s%s%s\n' "$C_DIM"  "$*"     "$C_OFF"; }
info() { printf '  %s\n' "$*"; }

pull_step() {
    section "📥" "PULL — GitHub → 홈"

    info "git pull origin"
    local before_hash after_hash
    before_hash=$(git rev-parse HEAD 2>/dev/null || echo "")
    if ! LC_ALL=C git pull --ff-only 2>&1 | sed 's/^/    /'; then
        err "ff-only pull 실패 — 수동 merge 필요"
        return 1
    fi
    after_hash=$(git rev-parse HEAD 2>/dev/null || echo "")
    if [[ "$before_hash" == "$after_hash" ]]; then
        ok "이미 최신 (변경 없음)"
    else
        local changed=$(git diff --name-only "$before_hash" "$after_hash" 2>/dev/null | wc -l | tr -d ' ')
        ok "$changed 파일 받음"
        git diff --name-only "$before_hash" "$after_hash" 2>/dev/null | head -5 | sed 's/^/    /'
        [[ $changed -gt 5 ]] && dim "...외 $((changed - 5))개"
    fi

    section "🏠" "APPLY — chezmoi → ~/.claude/, ~/.codex/"
    local apply_out
    apply_out=$(CHEZMOI_SKIP_BOOTSTRAP=1 chezmoi apply --force 2>&1) || true
    if [[ -z "$apply_out" ]]; then
        ok "변경 없음"
    else
        echo "$apply_out" | head -10 | sed 's/^/    /'
    fi

    section "🗑️ " "CLEANUP — 다른 PC에서 삭제된 스킬/팀 자동 정리"
    local removed=0
    for base in dot_claude/skills dot_codex/skills; do
        local home_base="$HOME/.${base#dot_}"
        [[ -d "$home_base" ]] || continue
        for home_item in "$home_base"/*/; do
            [[ -d "$home_item" ]] || continue
            local name=$(basename "${home_item%/}")
            [[ -L "${home_item%/}" ]] && continue
            [[ "$name" == .system || "$name" == codex-primary-runtime || "$name" == symlink_* ]] && continue
            if [[ ! -d "$REPO/$base/$name" ]]; then
                rm_ "$home_item"
                rm -rf "$home_item"
                ((removed++)) || true
            fi
        done
    done
    [[ $removed -eq 0 ]] && ok "삭제할 폴더 없음" || ok "$removed 개 폴더 정리"

    section "🧩" "PLUGIN SYNC — manifest 기준 install/uninstall"
    if ! command -v claude >/dev/null 2>&1; then
        warn "claude CLI 없음 → skip"
    else
        bash "$REPO/scripts/claude/install-plugins.sh" 2>&1 | sed 's/^/  /' || true
    fi

    section "🔌" "MCP SYNC — 경로 검증 + 등록"
    if ! command -v claude >/dev/null 2>&1; then
        warn "claude CLI 없음 → skip"
    else
        bash "$REPO/scripts/claude/install-mcp.sh" 2>&1 | sed 's/^/  /' || true
    fi

    section "✅" "PULL 완료 ($(date +%H:%M:%S))"
}

push_step() {
    section "🔄" "DSYNC PUSH (호스트: $HOSTNAME_SHORT)"

    # 0. git pull (로케일 무관, hash 비교로 판정)
    # `both` 모드에선 pull_step이 이미 pull 했으므로 skip
    if [[ "${DSYNC_PUSH_SKIP_PULL:-0}" == "1" ]]; then
        info "git pull skip (both 모드 — pull_step에서 이미 수행)"
    else
        info "git pull (다른 PC 변경 먼저 받기)"
        local before_hash after_hash
        before_hash=$(git rev-parse HEAD 2>/dev/null || echo "")
        if ! LC_ALL=C git pull --ff-only >/dev/null 2>&1; then
            err "ff-only pull 실패"
            return 1
        fi
        after_hash=$(git rev-parse HEAD 2>/dev/null || echo "")
        if [[ "$before_hash" == "$after_hash" ]]; then
            ok "이미 최신"
        else
            ok "$(git diff --name-only "$before_hash" "$after_hash" 2>/dev/null | wc -l | tr -d ' ') 파일 받음"
        fi
    fi

    # 1. manifest sync
    section "📋" "MANIFEST SYNC — 플러그인/마켓/MCP 자동 탐지"
    bash "$REPO/scripts/shared/sync-manifests.sh" 2>&1 | sed 's/^/  /'

    # 2. 삭제된 스킬/팀 forget
    section "🗑️ " "FORGET — 홈에서 삭제된 스킬/팀"
    local forgot=0
    for base in dot_claude/skills dot_codex/skills; do
        [[ -d "$REPO/$base" ]] || continue
        for src_item in "$REPO/$base"/*/; do
            [[ -d "$src_item" ]] || continue
            local name=$(basename "${src_item%/}")
            [[ "$name" == symlink_* || "$name" == .system || "$name" == codex-primary-runtime ]] && continue
            local home_item="$HOME/.${base#dot_}/$name"
            if [[ ! -d "$home_item" ]]; then
                rm_ "$name"
                chezmoi forget --force "$home_item" >/dev/null 2>&1 || true
                ((forgot++)) || true
            fi
        done
    done
    [[ $forgot -eq 0 ]] && ok "삭제 감지 없음" || ok "$forgot 개 forget"

    # 3. 새 스킬/팀 add
    section "➕" "ADD — 새 스킬/팀 자동 탐지"
    local added=0
    for base in "$HOME/.claude/skills" "$HOME/.codex/skills"; do
        [[ -d "$base" ]] || continue
        for item in "$base"/*/; do
            [[ -d "$item" ]] || continue
            local name=$(basename "${item%/}")
            [[ -L "${item%/}" ]] && continue
            [[ "$name" == .system || "$name" == codex-primary-runtime ]] && continue
            if [[ -z "$(chezmoi managed "${item%/}" 2>/dev/null)" ]]; then
                local rel_base="dot_${base#$HOME/.}"
                local src_dir="$REPO/$rel_base/$name"
                if compgen -G "$src_dir/*.tmpl" > /dev/null 2>&1; then
                    dim "$name — 기존 .tmpl 존재, skip"
                    continue
                fi
                add "$name"
                chezmoi add "${item%/}" >/dev/null 2>&1 || true
                ((added++)) || true
            fi
        done
    done
    [[ $added -eq 0 ]] && ok "새 항목 없음" || ok "$added 개 add"

    # 4. re-add (기존 파일 갱신)
    section "🔃" "RE-ADD — 기존 추적 파일 갱신"
    local readd_out
    readd_out=$(chezmoi re-add 2>&1) || true
    if [[ -z "$readd_out" ]]; then
        ok "변경 없음"
    else
        echo "$readd_out" | head -5 | sed 's/^/    /'
    fi

    # 5. 변경 summary + push
    section "📤" "COMMIT + PUSH"
    if [[ -z "$(git status --porcelain)" ]]; then
        ok "변경 없음 — push skip"
        section "✅" "DSYNC 완료 (변경 없음)"
        return 0
    fi

    # 변경 stats
    local stats=$(git diff --cached --stat HEAD 2>/dev/null | tail -1)
    [[ -z "$stats" ]] && stats=$(git diff --stat | tail -1)
    info "변경: $stats"

    # 카테고리별 분류
    local changed_files=$(git diff HEAD --name-only 2>/dev/null; git ls-files -o --exclude-standard 2>/dev/null)
    local n_skills=$(echo "$changed_files" | grep -cE "skills/" || true)
    local n_manifests=$(echo "$changed_files" | grep -cE "manifests/" || true)
    local n_md=$(echo "$changed_files" | grep -cE "\.md$" || true)
    local n_settings=$(echo "$changed_files" | grep -cE "settings\.json|config\.toml" || true)
    [[ $n_skills -gt 0 ]] && dim "스킬: $n_skills 파일"
    [[ $n_manifests -gt 0 ]] && dim "manifest: $n_manifests 파일"
    [[ $n_md -gt 0 ]] && dim "글로벌 룰(.md): $n_md 파일"
    [[ $n_settings -gt 0 ]] && dim "settings/config: $n_settings 파일"

    git add -A
    git commit -m "🔄 autosync from ${HOSTNAME_SHORT} ${TS}" >/dev/null
    git push >/dev/null 2>&1 && ok "GitHub push 완료" || { err "push 실패"; return 1; }

    section "✅" "DSYNC 완료 ($(date +%H:%M:%S))"
}

RC=0
case "$MODE" in
    pull)   pull_step || RC=$? ;;
    push)   push_step || RC=$? ;;
    both)   pull_step && DSYNC_PUSH_SKIP_PULL=1 push_step || RC=$? ;;
    diff)   chezmoi diff ;;
    cd)     cd "$REPO" && exec "${SHELL:-bash}" ;;
    status)
        section "📊" "DSYNC STATUS"
        info "host:    $HOSTNAME_SHORT"
        info "branch:  $(git branch --show-current)"
        info "ahead:   $(git rev-list --count @{u}..HEAD 2>/dev/null || echo 0) 개 commit (push 필요)"
        info "behind:  $(git rev-list --count HEAD..@{u} 2>/dev/null || echo 0) 개 commit (pull 필요)"
        info "홈↔dot:  $(chezmoi diff 2>/dev/null | wc -l) lines diff"
        ;;
    rm|remove)
        target="${2:-}"
        [[ -z "$target" ]] && { echo "Usage: dsync rm <path>"; exit 1; }
        [[ "$target" != /* ]] && target="$PWD/$target"
        section "🗑️ " "REMOVE: $target"
        chezmoi forget --force "$target" >/dev/null 2>&1 || true
        rm -rf "$target"
        cd "$REPO"
        git add -A
        if [[ -z "$(git status --porcelain)" ]]; then
            warn "변경 없음"
        else
            git commit -m "🗑️  remove $(basename "$target") from ${HOSTNAME_SHORT}" >/dev/null
            git push >/dev/null 2>&1
            ok "양쪽 PC에서 삭제 완료 (다른 PC: dsync pull)"
        fi
        ;;
    *)
        cat <<EOF
${B}dsync${C_OFF} — Claude Code + Codex 양방향 sync

Usage: dsync [command]
  ${B}push${C_OFF}        (기본) 홈 → dotfiles → GitHub
  ${B}pull${C_OFF}        GitHub → 홈
  ${B}both${C_OFF}        pull + push
  ${B}diff${C_OFF}        변경 미리보기
  ${B}status${C_OFF}      현재 상태
  ${B}rm <path>${C_OFF}   양쪽 PC sync 삭제
  ${B}cd${C_OFF}          repo로 이동
EOF
        exit 1
        ;;
esac

# pull/push의 실패 코드 최종 전파 (cron 등에서 실패 감지 가능)
exit "$RC"
