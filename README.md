<div align="center">

# agent-dotfiles

**여러 PC 사이에서 Claude Code + Codex 환경을 양방향 자동 동기화**

[chezmoi](https://www.chezmoi.io) + [age](https://github.com/FiloSottile/age) 기반 · macOS/Linux · public 템플릿

[![chezmoi](https://img.shields.io/badge/managed_by-chezmoi-blue)](https://www.chezmoi.io)
[![age](https://img.shields.io/badge/secrets-age-green)](https://github.com/FiloSottile/age)
[![review](https://img.shields.io/badge/code_review-24%2B_cycle-success)]()

</div>

---

## 어떤 문제를 해결하나

여러 PC(맥북·리눅스·회사·집)에서 Claude Code와 Codex를 동시에 쓰면 매번 따로 노는 것:

- `~/.claude/CLAUDE.md`, `~/.codex/AGENTS.md`, settings.json
- `~/.claude/skills/`, `~/.codex/skills/` 본인 작성 스킬
- 설치한 플러그인, 마켓플레이스, MCP 서버
- API 토큰 같은 시크릿

**`dsync` 한 단어로 양쪽 PC 양방향 sync.** 시크릿은 `age`로 암호화해서 안전하게 git에 commit.

---

## Features

| | |
|---|---|
| ⚡ | **한 줄 sync** — `dsync` 한 단어로 push/pull/diff/status/rm |
| 🔄 | **양방향 자동** — 추가/수정/삭제 모두 양쪽 PC 반영 |
| 🔍 | **자동 탐지** — 설치한 플러그인/마켓/MCP를 manifest로 추출 |
| 🔐 | **시크릿 암호화** — age 키 1개로 토큰 안전 보관 + 평문 토큰 누출 가드 |
| 🌐 | **크로스플랫폼** — macOS(arm64/intel) + Linux(amd64/arm64) 자동 감지 |
| 🎛️ | **인터랙티브 부트스트랩** — 새 PC 셋업 시 y/n 단계별 |
| 🧩 | **Claude/Codex 분리** — 한쪽만 sync도 가능 |
| 🛡️ | **24+ cycle 코드리뷰** — Claude + Codex 다중 검증 통과 |

---

## Quick Start

### 1. age 설치 + 마스터 키 생성

```bash
# age 설치
brew install age            # macOS
sudo apt install age        # Ubuntu/Debian
sudo pacman -S age          # Arch

# 마스터 키 생성 (이 키만 잃지 않게 백업 필수!)
mkdir -p ~/.config/chezmoi
age-keygen -o ~/.config/chezmoi/key.txt
chmod 600 ~/.config/chezmoi/key.txt

# public key 메모 (age1... 로 시작)
age-keygen -y ~/.config/chezmoi/key.txt
```

### 2. Fork + 한 줄 셋업

이 repo를 본인 GitHub로 fork. 그 다음:

```bash
sh -c "$(curl -fsLS get.chezmoi.io)" -- init --apply <Your-User>/agent-dotfiles
```

진행 순서 (자동):
1. chezmoi 바이너리 설치
2. repo clone → `~/.local/share/chezmoi/`
3. **age public key 프롬프트** ← 1단계 메모한 값 붙여넣기
4. `~/.config/chezmoi/chezmoi.toml` 자동 생성
5. dotfile 적용 (`~/.claude/`, `~/.codex/`)
6. `bootstrap.sh` 인터랙티브 실행 (플러그인/MCP/바이너리 y/n)

### 3. 다른 PC에서 합류

```bash
# 첫 PC에서 마스터 키 복사 (Tailscale / SCP / 1Password 등)
rsync -avz <첫-PC>:~/.config/chezmoi/key.txt ~/.config/chezmoi/
chmod 600 ~/.config/chezmoi/key.txt

# 같은 한 줄
sh -c "$(curl -fsLS get.chezmoi.io)" -- init --apply <Your-User>/agent-dotfiles
```

이후 양쪽 PC에서 `dsync` 한 단어면 끝.

---

## Daily Commands

### `dsync` — 한 단어

```bash
dsync           # = push (홈 → dotfiles → GitHub)
dsync push      # 명시적
dsync pull      # GitHub → 홈
dsync both      # pull + push
dsync diff      # 변경 미리보기
dsync status    # 한눈에 상태
dsync rm <path> # 양쪽 PC sync 삭제 (~/Path 또는 절대경로)
dsync cd        # repo로 이동 + 새 셸
```

### `dsync push` 자동 단계

1. `git pull --ff-only` (충돌이면 abort)
2. **manifest 자동 탐지** — `~/.claude/plugins/*.json`, `~/.claude.json` 기반 manifests/ 갱신
3. **삭제 감지** — 홈에서 지운 스킬 자동 forget
4. **추가 감지** — 새 스킬 폴더 자동 add
5. `chezmoi re-add` — 기존 추적 파일 갱신
6. **토큰 누출 가드** — manifest에 Bearer/sk-/ghp_/private key 등 패턴 발견 시 sync 중단
7. commit + push

### `dsync pull` 자동 단계

1. `git pull --ff-only` (로케일 무관, hash 비교)
2. **로컬 미동기 가드** — 홈에 push 안 된 변경 있으면 abort (`DSYNC_FORCE_APPLY=1`로 우회)
3. `chezmoi apply` (텍스트 파일/스킬/메모리)
4. **홈 cleanup** — `chezmoi managed` 기준으로 다른 PC에서 지운 스킬만 삭제
5. **플러그인 sync** — manifest 기준 install/uninstall (빈 manifest는 safety skip)
6. **MCP sync** — placeholder를 env로 expand + 경로 검증 + 없으면 ⚠ 경고 + skip

### Cron 자동화 (선택)

```cron
# 매시간 push
0 * * * * $HOME/.local/share/chezmoi/scripts/shared/auto-sync.sh push >> /tmp/dsync.log 2>&1
# 매일 새벽 pull
30 5 * * * $HOME/.local/share/chezmoi/scripts/shared/auto-sync.sh pull >> /tmp/dsync.log 2>&1
```

flock + mkdir 이중 lock으로 동시 실행 안전.

---

## What gets synced

### Claude Code (`~/.claude/`)

| ✅ 동기화 | ❌ 제외 |
|---|---|
| `CLAUDE.md` 등 글로벌 룰 | `.credentials.json` (재로그인이 안전) |
| `settings.json` (템플릿) | `plugins/cache/` (manifest로 재설치) |
| `keybindings.json`, statusline | `sessions/`, `transcripts/`, `history.jsonl` |
| `hooks/` | `telemetry/`, `paste-cache/`, `file-history/` |
| 본인 작성 스킬 (`skills/<your-skill>/`) | 외부 마켓 스킬 (manifest로 재설치) |
| `projects/.../memory/` (auto-memory) | Teams (프로젝트 일회성) |
| Manifest: 마켓/플러그인/MCP | |

### Codex (`~/.codex/`)

| ✅ 동기화 | ❌ 제외 |
|---|---|
| `AGENTS.md`, 추가 룰 문서 | `auth.json` (재로그인) |
| `config.toml` (시크릿 자동 복호화) | `sessions/`, `history.jsonl`, `*.sqlite` |
| 본인 작성 스킬 | `models_cache.json`, `installation_id` |

---

## 머신별 경로 차이 처리

옵시디언 vault, 본인 프로젝트 root 같은 **PC마다 다른 경로**는 환경변수로 처리.

각 PC에서 한 번 작성 (선택, 없어도 dsync 동작):

```bash
mkdir -p ~/.config/agent-dotfiles
cat > ~/.config/agent-dotfiles/env <<'EOF'
export OBSIDIAN_VAULT="$HOME/Project/vault"   # 본인 환경에 맞게
export PROJECTS_ROOT="$HOME/Project"
# 사용자가 어떤 변수명 쓰든 자동 인식
EOF
```

**작동 원리:**
- **push**: 절대경로가 env 변수 값과 일치하면 manifest에 `{{VARNAME}}`로 자동 역치환
- **pull**: manifest의 `{{VARNAME}}`을 그 PC env 값으로 expand 후 MCP 등록
- 경로 없으면 → 경고 + 어떤 변수 정의하면 되는지 안내

---

## 시크릿 관리

### 새 시크릿 추가

```bash
PUBKEY=$(age-keygen -y ~/.config/chezmoi/key.txt)
echo -n "토큰-값" | age -r "$PUBKEY" -o ~/.local/share/chezmoi/secrets/my_token.age

# 템플릿에서 참조 (settings.json.tmpl 또는 config.toml.tmpl):
#   "key": "{{ (decrypt (include "secrets/my_token.age")) | trim }}"

dsync
```

### 누출 방지 가드 (자동)

`sync-manifests.sh`가 manifest 생성 시 다음 패턴 감지 → sync 중단:

- `Bearer <token>`
- `sk-...`, `ghp_...`, `gho_...`, `github_pat_...`
- `token=`, `api_key=`, `secret_key=`, `password=` (URL/JSON/YAML)
- AWS `AKIA...`, Slack `xox[abps]-...`
- `BEGIN PRIVATE KEY` (RSA/EC/OPENSSH 등)

자세한 시크릿 관리(회전/마스터키 교체) → [`docs/SECRETS.md`](docs/SECRETS.md)

---

## 안전 가드 (`dsync rm`)

`dsync rm <path>`는 양쪽 PC sync 삭제. 다음 다층 가드:

1. **상대경로 거부** — 절대경로 또는 `~/` 시작만 허용
2. **보호 디렉토리** — `/`, `/etc`, `/usr`, `$HOME` 등 즉시 reject
3. **realpath 정규화** — `../` 또는 symlink로 HOME 밖 탈출 방지 (parent만 follow, target 자체는 X)
4. **HOME 직하 핵심** — `.ssh`, `.claude`, `.codex`, `.config`, `.gnupg`, `.aws` 등 직접 삭제 reject
5. **HOME 직하 1단계** — 5초 wait 경고 (Ctrl+C 취소 가능)
6. **symlink 보호** — symlink는 unlink만, 실제 target 디렉토리는 보존

---

## Project Structure

```
~/.local/share/chezmoi/         ← chezmoi가 자동 clone
├── README.md, bootstrap.sh, LICENSE
├── .chezmoi.toml.tmpl          # init 시 age recipient 프롬프트
├── .chezmoiignore, .gitignore
│
├── dot_claude/                 # → ~/.claude/  (각자 본인 거 채움)
│   ├── CLAUDE.md, settings.json.tmpl
│   ├── skills/                 # 본인 스킬
│   ├── hooks/
│   └── projects/.../memory/
│
├── dot_codex/                  # → ~/.codex/
│   ├── AGENTS.md, config.toml.tmpl
│   └── skills/
│
├── dot_local/private_bin/
│   └── executable_dsync        # → ~/.local/bin/dsync
│
├── manifests/                  # 선언적 인벤토리
│   ├── claude/{marketplaces.json, plugins.txt, mcp.json}
│   ├── codex/mcp.toml
│   └── personal-projects.json
│
├── scripts/
│   ├── claude/{install.sh, install-plugins.sh, install-mcp.sh}
│   ├── codex/{install.sh, install-mcp.sh}
│   └── shared/{auto-sync.sh, sync-manifests.sh, install-binaries.sh, clone-personal-projects.sh}
│
└── secrets/*.age               # age 암호화 시크릿
```

---

## Cross-platform 동작 원리

| 자동 처리 | 어떻게 |
|---|---|
| `/home/user` ↔ `/Users/user` | `{{ .chezmoi.homeDir }}` 템플릿 |
| Linux/macOS 분기 | `{{ .chezmoi.os }}` |
| Intel/Apple Silicon | `{{ .chezmoi.arch }}` |
| age 바이너리 다운로드 | OS/ARCH 감지 |
| Homebrew PATH (macOS) | 자동 추가 |
| nvm node 버전 | 설치된 모든 버전 PATH prepend |
| `sed -i` BSD/GNU 차이 | `sed -i.bak` + cleanup 패턴 |
| `flock` 없는 macOS | `mkdir` 원자적 lock fallback |
| `column -t` macOS 다름 | `awk printf`로 대체 |

---

## ⚠️ 스킬/MCP 의존성 주의

이 sync 시스템은 **파일을 옮기는 것**만 책임집니다. 스킬이나 MCP 안에 박힌 **절대경로/외부 도구 의존성**은 그대로 옮겨가므로 fork한 사람이 본인 환경에 맞게 직접 수정해야 합니다.

### 권장 패턴 (스킬 작성자용)

**SKILL.md에 placeholder + LLM 안내:**

```markdown
---
name: my-skill
description: ...
---

> **사용 전 확인 (LLM):** 이 스킬은 옵시디언 vault 경로가 필요합니다.
> `<USER_OBSIDIAN_VAULT>` placeholder는 자동 치환되지 **않습니다**.
> 처음 실행 시 사용자에게 경로를 물어보고 그 값으로 치환하세요.

기본 경로: `<USER_OBSIDIAN_VAULT>/notes/`
```

MCP는 manifest의 환경변수 placeholder + 각 PC env로 expand.

---

## FAQ

**Q. fork한 사람이 다른 사람 시크릿을 잘못 사용할 위험?**
A. `.chezmoi.toml.tmpl`이 init 시 본인 public key를 프롬프트로 받습니다. SECRETS.md 예시도 `$(age-keygen -y ~/.config/chezmoi/key.txt)`로 본인 키 자동 사용.

**Q. 양쪽 PC에서 동시에 다른 변경?**
A. `dsync push`가 `git pull --ff-only` 먼저. 충돌이면 abort + 안내. `chezmoi cd && git pull --rebase`로 수동 merge 후 다시 `dsync`.

**Q. project/local scope 플러그인은?**
A. `dsync`는 **user scope만** 다룸. project/local은 그 프로젝트 고유라 sync 대상 아님.

**Q. 마스터 키 잃어버리면?**
A. 모든 `*.age` 영구 복구 불가. **1Password/USB/종이 백업 필수** — `docs/SECRETS.md` 참고.

**Q. `dsync pull` 시 로컬 변경이 덮어쓰일 위험?**
A. `chezmoi re-add --dry-run` 가드로 abort. `DSYNC_FORCE_APPLY=1 dsync pull`로 명시 강제.

**Q. cron으로 자동 sync 시 한쪽이 stuck이면?**
A. flock(Linux) + mkdir lock(macOS) 이중 방어. 두 번째 dsync는 즉시 skip.

---

## Credit

원본 inspired by [Bae-ChangHyun's personal dotfiles](https://github.com/Bae-ChangHyun). 이 repo는 누구나 fork해서 쓸 수 있게 사용자 데이터 제거한 템플릿입니다.

## License

[MIT](LICENSE)
