# Secrets 관리 (age + chezmoi)

## 마스터 키

- 위치: `~/.config/chezmoi/key.txt`
- 권한: `chmod 600`
- **분실 시 모든 `*.age` 복구 불가** → 1Password / USB / 종이 백업 필수

```bash
# public key 확인 (공유 OK)
age-keygen -y ~/.config/chezmoi/key.txt

# 지문 (PC 간 같은지 비교용)
sha256sum ~/.config/chezmoi/key.txt
```

## 새 PC로 마스터 키 옮기기

```bash
# A. Tailscale rsync
rsync -avz <기존-PC>:~/.config/chezmoi/key.txt ~/.config/chezmoi/

# B. SCP
scp <기존-PC-IP>:~/.config/chezmoi/key.txt ~/.config/chezmoi/

# C. 1Password CLI
op document get "chezmoi-age-master-key" --out-file ~/.config/chezmoi/key.txt

# 어떤 방법이든 권한 잡기
chmod 600 ~/.config/chezmoi/key.txt
```

## 새 시크릿 추가

```bash
PUBKEY=$(age-keygen -y ~/.config/chezmoi/key.txt)

echo -n "토큰-값" | age -r $PUBKEY -o ~/.local/share/chezmoi/secrets/my_token.age

# 템플릿에서 참조 (예: dot_codex/config.toml.tmpl)
#   Authorization = "Bearer {{ (decrypt (include "secrets/my_token.age")) | trim }}"

dsync
```

## 시크릿 회전

```bash
echo -n "새-값" | age -r $PUBKEY -o ~/.local/share/chezmoi/secrets/my_token.age
dsync
```

## 마스터 키 회전 (노출 의심 시)

```bash
# 1. 백업
mv ~/.config/chezmoi/key.txt ~/.config/chezmoi/key.txt.old

# 2. 새 키
age-keygen -o ~/.config/chezmoi/key.txt
NEW_PUB=$(age-keygen -y ~/.config/chezmoi/key.txt)

# 3. 모든 secrets/*.age 재암호화
for f in ~/.local/share/chezmoi/secrets/*.age; do
    age -d -i ~/.config/chezmoi/key.txt.old "$f" | age -r "$NEW_PUB" -o "$f.new"
    mv "$f.new" "$f"
done

# 4. .chezmoi.toml.tmpl 안의 recipient 수정 후 chezmoi.toml 재생성
sed -i "s|recipient = \".*\"|recipient = \"$NEW_PUB\"|" ~/.local/share/chezmoi/.chezmoi.toml.tmpl
chezmoi init

# 5. 헌 키 삭제 + 커밋
rm ~/.config/chezmoi/key.txt.old
dsync
```

## 무엇이 시크릿이고 무엇이 아닌가

| 시크릿 ✅ | 시크릿 아님 ❌ |
|---|---|
| API 토큰, Bearer 토큰 | 마켓플레이스 URL |
| SSH 개인키 | 플러그인 활성 목록 |
| OAuth refresh token | 모델 이름, settings |
| DB 비밀번호 | 머신 경로 (`{{ .chezmoi.homeDir }}` 템플릿) |
