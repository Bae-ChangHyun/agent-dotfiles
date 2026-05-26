# 시크릿 관리 (`age` + chezmoi)

## 마스터 키

- **위치**: `~/.config/chezmoi/key.txt`
- **권한**: `chmod 600`
- **백업**: 이 키만 잃어버리면 모든 암호화된 secret이 복구 불가. **무조건 1Password/Keychain/물리적 백업 중 하나 이상**.
- **git에 절대 commit 금지** (`.gitignore`로 보호되지만 그래도 조심)

본인 public key 확인:
```bash
age-keygen -y ~/.config/chezmoi/key.txt
```

> ⚠️ **아래 모든 예시의 `age -r <PUBLIC_KEY>` 는 본인 키로 교체할 것.** `$(age-keygen -y ~/.config/chezmoi/key.txt)` 명령 치환을 쓰면 자동.

## 새 PC 셋업 — 키 이동 방법 3가지

### A. Tailscale rsync (제일 빠름)

```bash
# 기존 PC에서
rsync -avz ~/.config/chezmoi/key.txt <new-pc-tailscale-name>:~/.config/chezmoi/
```

### B. 1Password (모든 PC에 1Password 설치 시 가장 안전)

```bash
# 기존 PC에서: 1Password에 저장
op document create ~/.config/chezmoi/key.txt --title "chezmoi-age-master-key"

# 새 PC에서: 다운로드
mkdir -p ~/.config/chezmoi
op document get "chezmoi-age-master-key" --out-file ~/.config/chezmoi/key.txt
chmod 600 ~/.config/chezmoi/key.txt
```

### C. USB / 종이 (오프라인 백업)

```bash
# 백업
age-keygen -y ~/.config/chezmoi/key.txt  # public key (commit 가능)
cat ~/.config/chezmoi/key.txt            # private key (USB로 옮기거나 종이에)
```

## 새 시크릿 추가하기

예: API 토큰 새로 생겼을 때.

```bash
# 1. 본인 public key 가져와서 암호화 (반드시 본인 키 사용)
PUBKEY=$(age-keygen -y ~/.config/chezmoi/key.txt)
echo -n "my-new-secret-value" | age -r "$PUBKEY" \
    -o ~/.local/share/chezmoi/secrets/my_secret.age

# 2. 템플릿에서 참조
# settings.json.tmpl 또는 config.toml.tmpl 안에:
#   "api_key": "{{ (decrypt (include "secrets/my_secret.age")) | trim }}"

# 3. 적용
chezmoi apply

# 4. commit
cd ~/.local/share/chezmoi && git add secrets/my_secret.age && git commit -m "secret: my_secret"
```

## 기존 시크릿 회전

```bash
PUBKEY=$(age-keygen -y ~/.config/chezmoi/key.txt)
echo -n "new-rotated-value" | age -r "$PUBKEY" \
    -o ~/.local/share/chezmoi/secrets/<your-secret-name>.age

# 적용 + 커밋
chezmoi apply
cd ~/.local/share/chezmoi && git add secrets/ && git commit -m "rotate: <secret-name>"
```

## 마스터 키 회전 (모든 시크릿 재암호화)

키가 노출됐다고 의심되면:

```bash
# 1. 새 키 발급
mv ~/.config/chezmoi/key.txt ~/.config/chezmoi/key.txt.old
age-keygen -o ~/.config/chezmoi/key.txt

# 2. 새 public key 확인
NEW_PUB=$(age-keygen -y ~/.config/chezmoi/key.txt)

# 3. 모든 secrets/*.age 재암호화
for f in ~/.local/share/chezmoi/secrets/*.age; do
    age -d -i ~/.config/chezmoi/key.txt.old "$f" | age -r "$NEW_PUB" -o "$f.new"
    mv "$f.new" "$f"
done

# 4. .chezmoi.toml.tmpl 안의 recipient 업데이트 (macOS/Linux 호환)
TMPL=~/.local/share/chezmoi/.chezmoi.toml.tmpl
sed "s|recipient = \".*\"|recipient = \"$NEW_PUB\"|" "$TMPL" > "$TMPL.new" && mv "$TMPL.new" "$TMPL"

# 5. 헌 키 삭제
rm ~/.config/chezmoi/key.txt.old

# 6. 커밋 + 양쪽 PC 다시 init
cd ~/.local/share/chezmoi && git add . && git commit -m "rotate master key" && git push
# (각 PC) chezmoi init  # 새 recipient로 chezmoi.toml 갱신
```

## 무엇이 시크릿이고 무엇이 아닌가

| 시크릿 ✅ (age 암호화 필요) | 시크릿 아님 ❌ (평문 OK) |
|---|---|
| API 토큰, Bearer 토큰 | repo 이름, 마켓플레이스 URL |
| SSH 개인키 | 플러그인 활성 목록 |
| OAuth refresh token | model="claude-..." 같은 설정 |
| DB 비밀번호 | 머신 경로 (`{{ .chezmoi.homeDir }}` 템플릿) |
