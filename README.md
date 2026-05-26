# agent-dotfiles

> Claude Code + Codex 환경을 여러 PC 사이에서 양방향 자동 sync하는 [chezmoi](https://www.chezmoi.io) 기반 dotfiles 템플릿.
>
> fork → 본인 설정 채우기 → 어디서든 `dsync` 한 단어로 끝.

[![chezmoi](https://img.shields.io/badge/managed_by-chezmoi-blue)](https://www.chezmoi.io)
[![age](https://img.shields.io/badge/secrets-age-green)](https://github.com/FiloSottile/age)

---

## 어떤 문제를 해결하나

여러 PC(맥북/리눅스/회사/집)에서 Claude Code와 Codex를 동시에 쓰면 매번 다음이 따로 놀음:

- `~/.claude/CLAUDE.md`, `~/.codex/AGENTS.md`, settings.json
- `~/.claude/skills/`, `~/.codex/skills/` (본인이 작성한 것들)
- 설치한 플러그인, 마켓플레이스, MCP 서버
- API 토큰 같은 시크릿

`dsync` 한 줄로 **추가/수정/삭제** 모두 양방향 동기화. 시크릿은 `age`로 암호화해서 git에 안전하게 commit.

---

## Features

- ⚡ **한 줄 sync** — `dsync` 한 단어로 push/pull/status
- 🔄 **완전 양방향 자동** — 어느 PC에서 추가/삭제하든 다른 PC에 반영
- 🔍 **자동 탐지** — 설치한 플러그인/마켓/MCP를 manifest로 자동 추출
- 🔐 **시크릿 암호화** — age 키 1개로 토큰 안전 보관
- 🌐 **크로스플랫폼** — macOS(arm64/intel) + Linux(amd64/arm64) 자동 감지
- 🎛️ **인터랙티브 부트스트랩** — 새 PC 셋업 시 y/n으로 단계별 선택
- 🧩 **Claude/Codex 분리** — 둘 다 또는 한쪽만 sync 가능
- 📦 **선언적 인벤토리** — 플러그인 코드 없이 manifest만, 새 PC에서 자동 재설치

---

## Quick Start — 첫 사용자

### 1단계: fork

이 repo를 본인 GitHub로 fork (`Your-User/agent-dotfiles`).

### 2단계: 첫 PC에서 age 키 생성

```bash
# age 설치
brew install age            # macOS (Homebrew)
sudo apt install age        # Ubuntu/Debian
sudo pacman -S age          # Arch
# 또는 binary 직접 다운로드: https://github.com/FiloSottile/age/releases

# 마스터 키 생성
mkdir -p ~/.config/chezmoi
age-keygen -o ~/.config/chezmoi/key.txt
chmod 600 ~/.config/chezmoi/key.txt

# 본인 public key 확인 (age1... 로 시작)
age-keygen -y ~/.config/chezmoi/key.txt
```

이 public key를 메모.

### 3단계: chezmoi init (실행 순서 중요)

```bash
sh -c "$(curl -fsLS get.chezmoi.io)" -- init --apply <Your-User>/agent-dotfiles
```

위 명령이 자동으로 수행하는 순서:
1. chezmoi 바이너리 설치
2. repo를 `~/.local/share/chezmoi/`로 clone
3. **`age public key` 프롬프트 표시** ← 2단계 메모한 값(`age1...`) 붙여넣기
4. `~/.config/chezmoi/chezmoi.toml` 자동 생성 (recipient 박힘)
5. dotfile 적용 (`~/.claude/`, `~/.codex/`)
6. `run_once_after_99-bootstrap.sh` 자동 실행 → `bootstrap.sh` 인터랙티브 시작

이 한 줄이:
- chezmoi 설치
- repo clone
- 설정 파일 적용
- `bootstrap.sh` 인터랙티브 실행 (플러그인/MCP/바이너리 설치 y/n)

### 4단계: 다른 PC에서 합류

```bash
# 마스터 키 옮기기 (편한 방법)
rsync -avz <첫-PC>:~/.config/chezmoi/key.txt ~/.config/chezmoi/
chmod 600 ~/.config/chezmoi/key.txt

# 같은 한 줄
sh -c "$(curl -fsLS get.chezmoi.io)" -- init --apply <Your-User>/agent-dotfiles
```

이제 양쪽 PC에서 `dsync` 한 번이면 양방향 sync.

---

## Daily Commands

### `dsync` — 한 단어 (가장 자주)

```bash
dsync          # push (홈 → dotfiles → GitHub) — 기본
dsync push     # 명시적 push
dsync pull     # GitHub → 홈
dsync both     # pull + push
dsync diff     # 변경 미리보기
dsync status   # 한눈에 상태
dsync rm <path>  # 양쪽 PC에서 파일/스킬 sync 삭제
```

### `dsync push`가 자동으로 하는 것

1. `git pull` — 다른 PC 변경 먼저 받기
2. **manifest 자동 탐지** — 플러그인/마켓/MCP 현재 상태 → JSON 갱신
3. **삭제 감지** — 홈에서 지운 스킬 자동 forget
4. **추가 감지** — 새 스킬 폴더 자동 add
5. `chezmoi re-add` — 기존 파일 갱신
6. commit + push

### `dsync pull`이 자동으로 하는 것

1. `git pull` (로케일 무관, hash 비교)
2. `chezmoi apply` (텍스트 파일/스킬/메모리)
3. **홈 cleanup** — dotfiles에 없는 본인 폴더 자동 삭제
4. **플러그인 sync** — manifest에 맞춰 install/uninstall
5. **MCP sync** — placeholder를 머신별 env로 expand + 경로 존재 검증 + 없으면 ⚠ 경고 + skip

### 머신별 경로 변수 (`~/.config/agent-dotfiles/env`)

스킬/MCP가 PC마다 다른 경로(옵시디언 vault, 프로젝트 root 등)를 가리킬 때 사용. **선택사항** — 없어도 dsync 동작.

```bash
# 본인이 한 번 작성 (각 PC에 따로)
mkdir -p ~/.config/agent-dotfiles
cat > ~/.config/agent-dotfiles/env <<'EOF'
export OBSIDIAN_VAULT="$HOME/Project/vault"
export PROJECTS_ROOT="$HOME/Project"
# 본인이 정의한 변수면 무엇이든 OK — dsync가 자동 인식
EOF
```

작동 원리:
- **push**: 절대경로가 env 변수 값과 일치하면 manifest에 `{{VARNAME}}`로 자동 역치환
- **pull**: manifest의 `{{VARNAME}}`를 그 PC의 env 값으로 expand 후 등록
- 경로 없으면 → 경고 + 어떤 변수 정의하면 되는지 안내

### Cron으로 완전 자동화 (선택)

```bash
crontab -e
```
```cron
# 매시간 정각 push
0 * * * * $HOME/.local/share/chezmoi/scripts/shared/auto-sync.sh push >> /tmp/dotfiles.log 2>&1
# 매일 새벽 pull
30 5 * * * $HOME/.local/share/chezmoi/scripts/shared/auto-sync.sh pull >> /tmp/dotfiles.log 2>&1
```

---

## What gets synced

### Claude Code (`~/.claude/`)

| ✅ 동기화 | ❌ 제외 |
|---|---|
| `CLAUDE.md` 등 글로벌 룰 | `.credentials.json` (재로그인이 안전) |
| `settings.json` (템플릿) | `plugins/cache/` (manifest로 재설치) |
| `keybindings.json`, statusline 등 | `sessions/`, `transcripts/`, `history.jsonl` |
| `hooks/` | `telemetry/`, `paste-cache/`, `file-history/` |
| 본인 작성 스킬 (`skills/<your-skill>/`) | 외부 마켓플레이스 스킬 (manifest로 재설치) |
| `projects/.../memory/` (auto-memory) | Teams (프로젝트 일회성) |
| Manifest: 마켓/플러그인/MCP | |

### Codex (`~/.codex/`)

| ✅ 동기화 | ❌ 제외 |
|---|---|
| `AGENTS.md`, 추가 룰 문서 | `auth.json` (재로그인) |
| `config.toml` (시크릿 자동 복호화) | `sessions/`, `history.jsonl`, `*.sqlite` |
| 본인 작성 스킬 | `models_cache.json`, `installation_id` |

---

## 시크릿 추가

토큰/키 같은 거 추가하려면:

```bash
# 본인 age public key 확인
PUBKEY=$(age-keygen -y ~/.config/chezmoi/key.txt)

# 암호화해서 저장
echo -n "토큰-값" | age -r $PUBKEY -o ~/.local/share/chezmoi/secrets/my_token.age

# 템플릿(.tmpl)에서 참조
#   "key": "{{ (decrypt (include "secrets/my_token.age")) | trim }}"

dsync
```

자세히 → [`docs/SECRETS.md`](docs/SECRETS.md)

---

## Project Structure

```
~/.local/share/chezmoi/         ← chezmoi가 자동 clone
├── README.md, bootstrap.sh
├── .chezmoi.toml.tmpl          # 첫 init 시 age recipient 물어봄
├── .chezmoiignore, .gitignore
│
├── dot_claude/                 # → ~/.claude/  (각자 본인 거 채움)
│   ├── CLAUDE.md
│   ├── settings.json.tmpl
│   ├── skills/                 # 본인 스킬들
│   ├── hooks/
│   └── projects/.../memory/
│
├── dot_codex/                  # → ~/.codex/
│   ├── AGENTS.md
│   ├── config.toml.tmpl
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

---


---

## ⚠️ 스킬 / MCP / 인프라 의존 주의

이 sync 시스템은 **파일을 옮기는 것**만 책임집니다. 스킬이나 MCP 서버 안에 박힌 **절대경로/인프라 의존성**은 그대로 옮겨가므로, fork한 사람이 본인 PC에 맞게 **직접 수정**해야 합니다.

### 흔한 사례

| 패턴 | 어디서 자주 보임 | 본인이 해야 할 것 |
|---|---|---|
| `/Users/원래주인/obsidian_sync/...` | 옵시디언 의존 스킬 (SKILL.md) | 본인 vault 경로로 교체 또는 symlink |
| `~/.ai-newsletter/runtime` | 외부 도구 의존 스킬 | 그 도구를 깔거나 스킬 비활성화 |
| `{{HOME}}/Project/sub_project/personal/foo` | MCP stdio 서버 (mcp.json) | 본인 프로젝트 경로로 교체 |
| 본인이 만든 private repo MCP | manifests/claude/mcp.json | 본인 repo URL로 교체 또는 제거 |

### 권장 패턴

1. **SKILL.md에 절대경로 명시적 placeholder 사용**
   ```markdown
   기본 경로: `<USER_OBSIDIAN_VAULT>/notes/`
   ```
   상단에 "이 placeholder는 사용자에게 물어봐서 본인 경로로 사용" 안내.

2. **머신별 환경변수 파일 활용**
   `~/.config/agent-dotfiles/env`에 본인 PC만의 경로 export. dsync가 실행 시 자동 source.
   ```bash
   # ~/.config/agent-dotfiles/env (각 PC에 한 번)
   export OBSIDIAN_SYNC="$HOME/Project/vault"
   export PROJECTS_ROOT="$HOME/Project"
   ```

3. **symlink로 PC별 차이 흡수**
   ```bash
   ln -s "$HOME/Project/vault" "$HOME/obsidian_sync"
   ```
   양쪽 PC가 같은 경로로 보이게.

### Bash 환경변수 표기는 자동으로 풀리지 않음

```bash
${OBSIDIAN_SYNC:-$HOME/obsidian_sync}   # ← 이건 bash 문법
```
이걸 SKILL.md 안에 적어도 LLM이 자동 expansion 하지 않습니다. **LLM이 bash 명령으로 옮길 때만** bash가 풀어줍니다. 그러므로 신뢰성 떨어짐. placeholder + 사용자 prompt 패턴이 더 안전.


## FAQ

**Q. Mac에 `claude` CLI가 PATH에 없으면?**
A. `dsync pull`이 플러그인 sync 단계만 skip하고 나머지는 정상. Mac의 Claude Desktop 앱은 자체 PATH 처리하므로 보통 문제 안 됨.

**Q. 양쪽 PC에서 동시에 다른 변경했으면?**
A. `dsync push`가 `git pull --ff-only` 먼저. 충돌이면 멈춤. `chezmoi cd && git pull --rebase`로 수동 merge 후 다시 `dsync`.

**Q. project/local scope 플러그인은?**
A. `dsync`는 **user scope만** 다룸. project/local은 그 프로젝트 고유라 동기화 대상 아님.

**Q. 시크릿 마스터 키 잃어버리면?**
A. 모든 `*.age` 영구 복구 불가. **반드시** 1Password/USB/종이 백업 — `docs/SECRETS.md` 참고.

**Q. 스킬에 머신별 경로(옵시디언, ai-newsletter 등)가 박혀있으면?**
A. SKILL.md 안에 환경변수 사용 권장:
```
${OBSIDIAN_SYNC:-$HOME/obsidian_sync}
```
각 PC `.zshrc`에 `export OBSIDIAN_SYNC=...` 해두면 sync 시 그대로 옮겨도 PC별로 다르게 동작.

---

## Credit

원본 inspired by [Bae-ChangHyun's personal dotfiles](https://github.com/Bae-ChangHyun) — 본인 작품. 이 repo는 그걸 누구나 fork해서 쓸 수 있게 사용자 데이터 제거한 템플릿.

## License

MIT
