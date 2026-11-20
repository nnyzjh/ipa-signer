#!/usr/bin/env bash
# 临时签名：不用任何 Apple ID。
# 小白话：给安装包盖一个“自己认的章”，苹果不认，只能证明签名这一步在机器上跑得通，装不到真机上。
set -euo pipefail

OUT="${GITHUB_WORKSPACE:-$(pwd)}/out"
WORK="${IPA_WORK:-${RUNNER_TEMP:-/tmp}/ipa-work}"
APP="$WORK/Payload/Runner.app"
[ -d "$APP" ] || { echo "找不到 $APP，先跑 prepare-ipa.sh"; exit 1; }

{
  echo "## 2. 临时签名（adhoc）"
  echo
  echo "临时签名不用 Apple ID，签出来的包装不到真机上，只验证流程。"
  echo
} >> "$OUT/report.md"

echo "临时签名..."
codesign --force --sign - --deep --timestamp=none "$APP"

echo "检查签名..."
codesign --verify --deep --verbose=2 "$APP" >> "$OUT/report.md" 2>&1
codesign -dv "$APP" >> "$OUT/report.md" 2>&1

cd "$WORK"
rm -f "$OUT/signed.ipa"
ditto -c -k --sequesterRsrc --keepParent Payload "$OUT/signed.ipa"
ls -la "$OUT/signed.ipa"

{
  echo
  echo "- 临时签名完成，产物：out/signed.ipa（大小：$(du -h "$OUT/signed.ipa" | cut -f1)）"
  echo "- 注意：这是临时签名，装不到真机上。"
  echo
} >> "$OUT/report.md"
