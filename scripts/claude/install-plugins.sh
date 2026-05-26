#!/usr/bin/env bash
# Claude 플러그인/마켓플레이스를 manifest와 동기화.
# manifest에 있는 거 → install / 없는 거 → uninstall (양방향 sync)
set -euo pipefail

REPO_ROOT="${REPO_ROOT:-$HOME/.local/share/chezmoi}"
MARKETPLACES="$REPO_ROOT/manifests/claude/marketplaces.json"
PLUGINS="$REPO_ROOT/manifests/claude/plugins.txt"

log() { printf '\033[1;35m[claude/plugins]\033[0m %s\n' "$*"; }

if ! command -v claude >/dev/null 2>&1; then
    log "⊘ claude CLI 없음 (PATH 미설정) — 플러그인 sync skip"
    exit 0
fi
command -v jq >/dev/null 2>&1 || { log "❌ jq 필요"; exit 1; }

# ---------------- 마켓플레이스 sync ----------------
WANT_MKT=$(jq -r '.marketplaces[].name' "$MARKETPLACES" | sort -u)
HAVE_MKT=$(claude plugin marketplace list 2>/dev/null | awk -F'❯ ' '/❯ /{print $2}' | sort -u)

# 추가할 마켓 (WANT - HAVE)
to_add_mkt=$(comm -23 <(echo "$WANT_MKT") <(echo "$HAVE_MKT"))
if [[ -n "$to_add_mkt" ]]; then
    log "마켓플레이스 추가:"
    echo "$to_add_mkt" | while read name; do
        [[ -z "$name" ]] && continue
        src=$(jq -r ".marketplaces[] | select(.name==\"$name\") | (.repo // .url)" "$MARKETPLACES")
        log "  + $name ($src)"
        claude plugin marketplace add "$src" 2>&1 | sed 's/^/    /' || true
    done
fi

# 제거할 마켓 (HAVE - WANT)
to_rm_mkt=$(comm -13 <(echo "$WANT_MKT") <(echo "$HAVE_MKT"))
if [[ -n "$to_rm_mkt" ]]; then
    log "마켓플레이스 제거 (manifest에 없음):"
    echo "$to_rm_mkt" | while read name; do
        [[ -z "$name" ]] && continue
        log "  - $name"
        claude plugin marketplace remove "$name" 2>&1 | sed 's/^/    /' || true
    done
fi

# catalog 갱신
log "marketplace update (catalog 갱신)"
claude plugin marketplace update 2>&1 | sed 's/^/    /' || true

# ---------------- 플러그인 sync (USER SCOPE 한정) ----------------
# project/local scope 플러그인은 그 프로젝트 전용 → dsync는 건드리지 않음
WANT_PLG=$(grep -vE '^\s*(#|$)' "$PLUGINS" | awk '{print $1}' | sort -u)
HAVE_PLG=$(jq -r '
    .plugins | to_entries[] |
    select(.value | map(.scope) | index("user")) |
    .key
' "$HOME/.claude/plugins/installed_plugins.json" 2>/dev/null | sort -u)

# 설치 (WANT - HAVE)
to_inst=$(comm -23 <(echo "$WANT_PLG") <(echo "$HAVE_PLG"))
if [[ -n "$to_inst" ]]; then
    log "플러그인 설치:"
    echo "$to_inst" | while read plg; do
        [[ -z "$plg" ]] && continue
        scope=$(grep -E "^$plg\s" "$PLUGINS" | awk '{print $2}')
        scope=${scope:-user}
        log "  + $plg (scope=$scope)"
        claude plugin install "$plg" --scope "$scope" 2>&1 | sed 's/^/    /' || true
    done
fi

# 제거 (HAVE - WANT)
to_uninst=$(comm -13 <(echo "$WANT_PLG") <(echo "$HAVE_PLG"))
if [[ -n "$to_uninst" ]]; then
    log "플러그인 제거 (manifest에 없음):"
    echo "$to_uninst" | while read plg; do
        [[ -z "$plg" ]] && continue
        log "  - $plg"
        claude plugin uninstall "$plg" 2>&1 | sed 's/^/    /' || true
    done
fi

# 변경 없을 때
if [[ -z "$to_add_mkt$to_rm_mkt$to_inst$to_uninst" ]]; then
    log "✓ 모든 플러그인/마켓이 manifest와 일치"
else
    log "✓ 동기화 완료"
fi
