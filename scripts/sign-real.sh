#!/usr/bin/env bash
# 真签名：用 Secrets 里的开发者证书（.p12）+ 描述文件（.mobileprovision）。
# 小白话：用苹果发的“身份证 + 准装证”给安装包盖真章，盖完就能装到手机上。
set -euo pipefail

OUT="${GITHUB_WORKSPACE:-$(pwd)}/out"
WORK="${IPA_WORK:-${RUNNER_TEMP:-/tmp}/ipa-work}"
APP="$WORK/Payload/Runner.app"
[ -d "$APP" ] || { echo "找不到 $APP，先跑 prepare-ipa.sh"; exit 1; }

: "${P12_BASE64:?缺少 Secret P12_BASE64（开发者证书 .p12 的 base64）}"
: "${P12_PASSWORD:?缺少 Secret P12_PASSWORD（.p12 的密码）}"
: "${MOBILEPROVISION_BASE64:?缺少 Secret MOBILEPROVISION_BASE64（描述文件 .mobileprovision 的 base64）}"

{
  echo "## 2. 真签名（开发者证书 + 描述文件）"
  echo
} >> "$OUT/report.md"

# ---- 临时钥匙串（用完就删，不留证书）----
KEYCHAIN="$WORK/build.keychain"
KEYCHAIN_PASSWORD="$(openssl rand -hex 16)"
rm -f "$KEYCHAIN-db" "$KEYCHAIN"
security create-keychain -p "$KEYCHAIN_PASSWORD" "$KEYCHAIN"
security set-keychain-settings -lut 21600 "$KEYCHAIN"
security unlock-keychain -p "$KEYCHAIN_PASSWORD" "$KEYCHAIN"

cleanup() {
  security delete-keychain "$KEYCHAIN" 2>/dev/null || true
  rm -f "$WORK/cert.p12" "$WORK/profile.mobileprovision" "$WORK/profile-cert.der"
}
trap cleanup EXIT

echo "导入证书..."
echo "$P12_BASE64" | base64 --decode -o "$WORK/cert.p12"
security import "$WORK/cert.p12" -k "$KEYCHAIN" -P "$P12_PASSWORD" -T /usr/bin/codesign
security set-key-partition-list -S apple-tool:,apple:,codesign: -s -k "$KEYCHAIN_PASSWORD" "$KEYCHAIN"
security list-keychains -d user -s "$KEYCHAIN"

IDENTITY=$(security find-identity -v -p codesigning "$KEYCHAIN" | awk '/Apple Development|iPhone Developer|Apple Distribution|iPhone Distribution/ {print $2; exit}')
[ -n "$IDENTITY" ] || {
  echo ".p12 里没找到签名证书，可能文件不对或密码不对"
  security find-identity -v -p codesigning "$KEYCHAIN"
  exit 1
}
echo "证书指纹：$IDENTITY"

# ---- 解析描述文件 ----
echo "解析描述文件..."
echo "$MOBILEPROVISION_BASE64" | base64 --decode -o "$WORK/profile.mobileprovision"
security cms -D -i "$WORK/profile.mobileprovision" > "$WORK/profile.plist"

python3 - "$WORK/profile.plist" "$WORK" <<'PYEOF'
import plistlib, sys, subprocess, datetime
plist_path, work = sys.argv[1], sys.argv[2]
d = plistlib.load(open(plist_path, 'rb'))
uuid = d['UUID']
exp = d['ExpirationDate']
ent = d.get('Entitlements', {})
appid = ent.get('application-identifier', '')
team = d.get('TeamIdentifier', [''])[0]
name = d.get('Name', '')
certs = d.get('DeveloperCertificates', [])
fp = ''
if certs:
    open(f'{work}/profile-cert.der', 'wb').write(certs[0])
    out = subprocess.run(['openssl', 'x509', '-inform', 'DER',
                          '-in', f'{work}/profile-cert.der',
                          '-fingerprint', '-sha1', '-noout'],
                         capture_output=True, text=True)
    fp = out.stdout.strip().replace('SHA1 Fingerprint=', '').replace(':', '')
now = datetime.datetime.now(datetime.timezone.utc)
days = (exp - now).days
with open(f'{work}/profile-info.txt', 'w') as f:
    f.write(f"UUID={uuid}\nEXP={exp.isoformat()}\nAPPID={appid}\nTEAM={team}\nNAME={name}\nCERTFP={fp}\nDAYS_LEFT={days}\n")
print('描述文件：', name)
print('UUID：', uuid)
print('过期：', exp, '，还剩', days, '天')
print('包名：', appid)
print('证书指纹：', fp)
PYEOF

# shellcheck disable=SC1091
source "$WORK/profile-info.txt"

# ---- 三项比对，对不上就停下 ----
PROFILE_BUNDLE_ID="${APPID#*.}"
APP_BUNDLE_ID=$(/usr/libexec/PlistBuddy -c "Print :CFBundleIdentifier" "$APP/Info.plist")
if [ "$PROFILE_BUNDLE_ID" != "*" ] && [ "$PROFILE_BUNDLE_ID" != "$APP_BUNDLE_ID" ]; then
  echo "描述文件是给 $PROFILE_BUNDLE_ID 用的，和这个安装包的 $APP_BUNDLE_ID 对不上，停下"
  exit 1
fi
if [ "$CERTFP" != "$IDENTITY" ]; then
  echo "描述文件里的证书和 .p12 里的证书不是同一个，停下"
  exit 1
fi
if [ "$DAYS_LEFT" -lt 0 ]; then
  echo "描述文件已过期（过期：$EXP），停下"
  exit 1
fi
echo "比对通过：包名一致、证书一致、描述文件还剩 $DAYS_LEFT 天"

# ---- 取出权限清单，装进包里，签名 ----
python3 - "$WORK/profile.plist" "$WORK/entitlements.plist" <<'PYEOF'
import plistlib, sys
d = plistlib.load(open(sys.argv[1], 'rb'))
plistlib.dump(d.get('Entitlements', {}), open(sys.argv[2], 'wb'))
print('已从描述文件取出权限清单')
PYEOF

mkdir -p ~/Library/MobileDevice/Provisioning\ Profiles
cp "$WORK/profile.mobileprovision" ~/Library/MobileDevice/Provisioning\ Profiles/"$UUID.mobileprovision"
cp "$WORK/profile.mobileprovision" "$APP/embedded.mobileprovision"

echo "真签名..."
codesign --force --sign "$IDENTITY" --entitlements "$WORK/entitlements.plist" --deep --timestamp "$APP"

cd "$WORK"
rm -f "$OUT/signed.ipa"
ditto -c -k --sequesterRsrc --keepParent Payload "$OUT/signed.ipa"
ls -la "$OUT/signed.ipa"

{
  echo "- 描述文件：$NAME，UUID：$UUID，还剩 $DAYS_LEFT 天"
  echo "- 包名：$APP_BUNDLE_ID，证书指纹：$IDENTITY"
  echo "- 真签名完成，产物：out/signed.ipa（大小：$(du -h "$OUT/signed.ipa" | cut -f1)）"
  echo
} >> "$OUT/report.md"
