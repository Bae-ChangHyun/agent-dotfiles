#!/usr/bin/env bash
# 본인 프로젝트 git clone + 초기 setup.
# manifests/personal-projects.json 읽음.
set -euo pipefail

REPO_ROOT="${REPO_ROOT:-$HOME/.local/share/chezmoi}"
MANIFEST="$REPO_ROOT/manifests/personal-projects.json"

log() { printf '\033[1;32m[clone]\033[0m %s\n' "$*"; }

command -v jq >/dev/null 2>&1 || { log "❌ jq 필요"; exit 1; }

# 머신별 env source (PROJECTS_ROOT 등)
[[ -f "$HOME/.config/agent-dotfiles/env" ]] && source "$HOME/.config/agent-dotfiles/env" || true

jq -c '.projects[]' "$MANIFEST" | while read -r p; do
    name=$(echo "$p" | jq -r '.name')
    repo=$(echo "$p" | jq -r '.repo')
    raw_path=$(echo "$p" | jq -r '.path')
    # 안전한 expand: ${VAR:-default}와 $HOME만 정규식으로 처리. eval은 코드 인젝션 위험.
    # ${VAR:-default} 패턴 처리
    if [[ "$raw_path" =~ \$\{([A-Za-z_][A-Za-z0-9_]*):-([^}]*)\} ]]; then
        var="${BASH_REMATCH[1]}"
        default="${BASH_REMATCH[2]}"
        value="${!var:-$default}"
        # default 안에 $HOME 등이 있으면 다시 한 번 처리
        value="${value//\$HOME/$HOME}"
        path="${raw_path/\$\{${var}:-${default}\}/$value}"
    else
        path="$raw_path"
    fi
    # 남은 $HOME 처리
    path="${path//\$HOME/$HOME}"
    # 안전성 검증: shell 메타문자 있으면 차단
    if [[ "$path" == *'`'* || "$path" == *'$('* || "$path" == *';'* || "$path" == *'|'* ]]; then
        log "⚠ $name — path에 셸 메타문자 발견, 차단: $raw_path"
        continue
    fi

    if [[ "$repo" == TODO:* ]]; then
        log "⊘ $name — repo URL 미설정 (manifests/personal-projects.json 수정 필요)"
        continue
    fi

    if [[ -d "$path/.git" ]]; then
        log "✓ $name 이미 있음 — pull"
        git -C "$path" pull --ff-only 2>&1 | sed 's/^/    /' || true
    else
        log "+ $name clone → $path"
        mkdir -p "$(dirname "$path")"
        if [[ "$repo" == http* ]] || [[ "$repo" == git@* ]]; then
            git clone "$repo" "$path" || { log "⚠ $name clone 실패 (권한/네트워크 확인) — 다음 항목으로 진행"; continue; }
        else
            gh repo clone "$repo" "$path" || { log "⚠ $name clone 실패 (gh 인증/권한 확인) — 다음 항목으로 진행"; continue; }
        fi
    fi

    # setup 명령 — 사용자 명시 동의 후 실행 (manifest는 git에 commit되는 평문이므로,
    # 악의적 PR/fork 시 임의 명령 실행 위험. 기본은 출력만 하고 사용자 확인 후 실행)
    setup_cmds=$(echo "$p" | jq -r '.setup[]?' 2>/dev/null || true)
    if [[ -n "$setup_cmds" ]]; then
        log "  ▶ setup 명령 (manifest에 정의됨):"
        echo "$setup_cmds" | sed 's/^/      /'
        if [[ "${DSYNC_AUTO_SETUP:-0}" == "1" ]]; then
            cd "$path"
            while IFS= read -r cmd; do
                [[ -z "$cmd" ]] && continue
                log "    ▶ 실행: $cmd"
                bash -c "$cmd" 2>&1 | sed 's/^/      /' || true
            done <<< "$setup_cmds"
        else
            log "    (스킵 — 명령 검토 후 실행하려면: DSYNC_AUTO_SETUP=1 dsync ...)"
        fi
    fi
done

log "✓ 개인 프로젝트 셋업 완료"
