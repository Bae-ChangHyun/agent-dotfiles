#!/usr/bin/env bash
# Claude 플러그인/마켓플레이스를 manifest와 동기화.
set -euo pipefail

REPO_ROOT="${REPO_ROOT:-$HOME/.local/share/chezmoi}"
MARKETPLACES="$REPO_ROOT/manifests/claude/marketplaces.json"
PLUGINS="$REPO_ROOT/manifests/claude/plugins.txt"

C_OK=$(tput setaf 2 2>/dev/null || echo "")
C_ADD=$(tput setaf 2 2>/dev/null || echo "")
C_RM=$(tput setaf 1 2>/dev/null || echo "")
C_DIM=$(tput setaf 8 2>/dev/null || echo "")
C_OFF=$(tput sgr0 2>/dev/null || echo "")

if ! command -v claude >/dev/null 2>&1; then
    printf '  %s⊘%s claude CLI 없음 → plugin sync skip\n' "$C_DIM" "$C_OFF"
    exit 0
fi
command -v jq >/dev/null 2>&1 || { echo "  ✗ jq 필요"; exit 1; }

# ---- 마켓플레이스 sync ----
# grep -v으로 빈 줄 제거 — comm은 비어있는 입력에 echo "" 한 줄을 받으면 오작동
WANT_MKT=$(jq -r '.marketplaces[].name // empty' "$MARKETPLACES" | sort -u | (grep -v '^$' || true) || true)
HAVE_MKT=$(claude plugin marketplace list 2>/dev/null | awk -F'❯ ' '/❯ /{print $2}' | sort -u | (grep -v '^$' || true) || true)

# counter 변수 제거 (pipe subshell이라 부모에 반영 안 되므로 미신뢰)
to_add_mkt=$(comm -23 <(printf '%s\n' "$WANT_MKT" | (grep -v '^$' || true)) <(printf '%s\n' "$HAVE_MKT" | (grep -v '^$' || true)))
if [[ -n "$to_add_mkt" ]]; then
    echo "$to_add_mkt" | while read name; do
        [[ -z "$name" ]] && continue
        src=$(jq -r --arg n "$name" '.marketplaces[] | select(.name==$n) | (.repo // .url)' "$MARKETPLACES")
        printf '  %s+%s 마켓 추가: %s (%s)\n' "$C_ADD" "$C_OFF" "$name" "$src"
        claude plugin marketplace add "$src" >/dev/null 2>&1 || true
    done
fi
to_rm_mkt=$(comm -13 <(printf '%s\n' "$WANT_MKT" | (grep -v '^$' || true)) <(printf '%s\n' "$HAVE_MKT" | (grep -v '^$' || true)))
if [[ -n "$to_rm_mkt" ]]; then
    echo "$to_rm_mkt" | while read name; do
        [[ -z "$name" ]] && continue
        printf '  %s-%s 마켓 제거: %s\n' "$C_RM" "$C_OFF" "$name"
        claude plugin marketplace remove "$name" >/dev/null 2>&1 || true
    done
fi

# catalog 갱신
claude plugin marketplace update >/dev/null 2>&1 || true

# ---- 플러그인 sync (user scope) ----
WANT_PLG=$(grep -vE '^[[:space:]]*(#|$)' "$PLUGINS" 2>/dev/null | awk '{print $1}' | sort -u | (grep -v '^$' || true) || true)
HAVE_PLG=$(jq -r '
    .plugins | to_entries[] |
    select(.value | map(.scope) | index("user")) |
    .key
' "$HOME/.claude/plugins/installed_plugins.json" 2>/dev/null | sort -u | (grep -v '^$' || true) || true)

# counter 변수 제거
to_inst=$(comm -23 <(printf '%s\n' "$WANT_PLG" | (grep -v '^$' || true)) <(printf '%s\n' "$HAVE_PLG" | (grep -v '^$' || true)))
if [[ -n "$to_inst" ]]; then
    echo "$to_inst" | while read plg; do
        [[ -z "$plg" ]] && continue
        printf '  %s+%s 플러그인 설치: %s\n' "$C_ADD" "$C_OFF" "$plg"
        claude plugin install "$plg" --scope user >/dev/null 2>&1 || printf '    %s(설치 실패)%s\n' "$C_DIM" "$C_OFF"
    done
fi
to_uninst=$(comm -13 <(printf '%s\n' "$WANT_PLG" | (grep -v '^$' || true)) <(printf '%s\n' "$HAVE_PLG" | (grep -v '^$' || true)))
if [[ -n "$to_uninst" ]]; then
    echo "$to_uninst" | while read plg; do
        [[ -z "$plg" ]] && continue
        printf '  %s-%s 플러그인 제거: %s\n' "$C_RM" "$C_OFF" "$plg"
        claude plugin uninstall "$plg" --scope user >/dev/null 2>&1 || printf '    %s(제거 실패)%s\n' "$C_DIM" "$C_OFF"
    done
fi

if [[ -z "$to_add_mkt$to_rm_mkt$to_inst$to_uninst" ]]; then
    printf '  %s✓%s 모든 플러그인/마켓이 manifest와 일치\n' "$C_OK" "$C_OFF"
else
    printf '  %s✓%s sync 완료\n' "$C_OK" "$C_OFF"
fi
