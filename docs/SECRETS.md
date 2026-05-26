# 시크릿 관리 (`age` + chezmoi)

## 마스터 키

- **위치**: `~/.config/chezmoi/key.txt`
- **권한**: `chmod 600`
- **백업**: 이 키만 잃어버리면 모든 암호화된 secret이 복구 불가. **무조건 1Password/Keychain/물리적 백업 중 하나 이상**.
- **git에 절대 commit 금지** (`.gitignore`로 보호되지만 그래도 조심)

공개 키 (이걸로 암호화함): `age1ycr4k73pw7uky9p5txy4dqy6s78u6xcnn83r74qa43u0l5wsuuxqp0nkwk`

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
# 1. 암호화
echo -n "my-new-secret-value" | age -r age1ycr4k73pw7uky9p5txy4dqy6s78u6xcnn83r74qa43u0l5wsuuxqp0nkwk \
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
# 1. 새 값으로 덮어쓰기
echo -n "new-rotated-value" | age -r age1ycr4k73pw7uky9p5txy4dqy6s78u6xcnn83r74qa43u0l5wsuuxqp0nkwk \
    -o ~/.local/share/chezmoi/secrets/refero_token.age

# 2. 적용 + 커밋
chezmoi apply
cd ~/.local/share/chezmoi && git add secrets/refero_token.age && git commit -m "rotate: refero token"
```

## 마스터 키 회전 (모든 시크릿 재암호화)

키가 노출됐다고 의심되면:

```bash
# 1. 새 키 발급
mv ~/.config/chezmoi/key.txt ~/.config/chezmoi/key.txt.old
age-keygen -o ~/.config/chezmoi/key.txt

# 2. 새 public key 확인
NEW_PUB=$(grep "public key" ~/.config/chezmoi/key.txt | awk '{print $NF}')

# 3. 모든 secrets/*.age 재암호화
for f in ~/.local/share/chezmoi/secrets/*.age; do
    age -d -i ~/.config/chezmoi/key.txt.old "$f" | age -r "$NEW_PUB" -o "$f.new"
    mv "$f.new" "$f"
done

# 4. .chezmoi.toml.tmpl 안의 recipient 업데이트
# macOS/Linux 호환: sed -i 사용법이 BSD vs GNU 다름 → in-place 안 쓰고 임시파일 경유
TMPL=~/.local/share/chezmoi/.chezmoi.toml.tmpl
sed "s|recipient = \".*\"|recipient = \"$NEW_PUB\"|" "$TMPL" > "$TMPL.new" && mv "$TMPL.new" "$TMPL"

# 5. 헌 키 삭제
rm ~/.config/chezmoi/key.txt.old

# 6. 커밋
cd ~/.local/share/chezmoi && git add . && git commit -m "rotate master key"
```

## 무엇이 시크릿이고 무엇이 아닌가?

| 시크릿 ✅ (age로 암호화) | 시크릿 아님 ❌ (평문 OK) |
|---|---|
| API 토큰, Bearer 토큰 | repo 이름, 마켓플레이스 URL |
| SSH 개인키 | 플러그인 활성 목록 |
| OAuth refresh token | model="claude-opus-4-7" 같은 설정 |
| DB 비밀번호 | `/home/bch/` 같은 머신 경로 (템플릿) |
| `.credentials.json` 전체 | `oracle-a1.md` 내 OCID (public 식별자) |

⚠️ **Oracle a1.md 안의 instance OCID는 시크릿이 아님** — Oracle 측에서도 비공개 처리하지 않음. SSH 키나 OCI 사설키만 보호하면 됨.
