#!/usr/bin/env bash
# 下载官方未签名的包，解出 Runner.app，打成未签名的 .ipa。
# 小白话：先把安装包的“半成品”下载下来，整理成一个能签名的样子。
set -euo pipefail

OUT="${GITHUB_WORKSPACE:-$(pwd)}/out"
WORK="${IPA_WORK:-${RUNNER_TEMP:-/tmp}/ipa-work}"
IPA_URL="${IPA_URL:-https://github.com/OpenListApp/OpenListApp/releases/download/v2025.07.292/ios-release.zip}"
BUNDLE_ID="${BUNDLE_ID:-com.github.openlist.openlist}"

mkdir -p "$OUT" "$WORK"
: > "$OUT/report.md"

{
  echo "## 1. 准备未签名的 IPA"
  echo
  echo "- 下载地址：$IPA_URL"
} >> "$OUT/report.md"

echo "下载未签名的包..."
curl -sSL -o "$WORK/release.zip" "$IPA_URL"
ls -la "$WORK/release.zip"

echo "解包..."
rm -rf "$WORK/unpacked" "$WORK/Payload"
unzip -q -o "$WORK/release.zip" -d "$WORK/unpacked"
APP="$WORK/unpacked/build/ios/archive/Runner.xcarchive/Products/Applications/Runner.app"
[ -d "$APP" ] || { echo "没找到 Runner.app，包结构变了"; exit 1; }

BUNDLE_ID_ACTUAL=$(/usr/libexec/PlistBuddy -c "Print :CFBundleIdentifier" "$APP/Info.plist")
VERSION=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$APP/Info.plist")
echo "包名：$BUNDLE_ID_ACTUAL，版本：$VERSION"
if [ "$BUNDLE_ID_ACTUAL" != "$BUNDLE_ID" ]; then
  echo "警告：包名和预期的 $BUNDLE_ID 不一样，继续跑（描述文件要按实际包名建）"
fi

# 确认确实没签名（codesign 查未签名的包会报错退出，属于正常现象）
if codesign -dv "$APP" 2>/dev/null; then
  echo "注意：Runner.app 已带签名"
  echo "- 顶层签名：已存在（不是全新的未签名包）" >> "$OUT/report.md"
else
  echo "确认：Runner.app 未签名"
  echo "- 顶层签名：无（确认是未签名包）" >> "$OUT/report.md"
fi

mkdir -p "$WORK/Payload"
cp -a "$APP" "$WORK/Payload/"
cd "$WORK"
ditto -c -k --sequesterRsrc --keepParent Payload "$WORK/unsigned.ipa"
echo "未签名 IPA 已生成：$WORK/unsigned.ipa"
ls -la "$WORK/unsigned.ipa"

{
  echo "- 包名：$BUNDLE_ID_ACTUAL，版本：$VERSION"
  echo "- 未签名 IPA 大小：$(du -h "$WORK/unsigned.ipa" | cut -f1)，SHA256：$(shasum -a 256 "$WORK/unsigned.ipa" | cut -d' ' -f1)"
  echo
} >> "$OUT/report.md"
