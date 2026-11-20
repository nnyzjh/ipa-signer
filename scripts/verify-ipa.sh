#!/usr/bin/env bash
# 检查签好的包：签名在不在、验不验得过、文件全不全。
# 小白话：盖完章之后再检查一遍，章是不是真的盖上了、包有没有缺东西。
# 注意：这里不用 set -e，验签失败也要把结果写进报告，再决定退出码。
set -uo pipefail

OUT="${GITHUB_WORKSPACE:-$(pwd)}/out"
WORK="${IPA_WORK:-${RUNNER_TEMP:-/tmp}/ipa-work}"
IPA="$OUT/signed.ipa"

{
  echo "## 3. 验签"
  echo
} >> "$OUT/report.md"

FAIL=0

if [ ! -f "$IPA" ]; then
  echo "- 没找到签好的包 out/signed.ipa" >> "$OUT/report.md"
  exit 1
fi

rm -rf "$WORK/verify" && mkdir -p "$WORK/verify"
unzip -q -o "$IPA" -d "$WORK/verify"
VAPP="$WORK/verify/Payload/Runner.app"
if [ ! -d "$VAPP" ]; then
  echo "- 包里没有 Payload/Runner.app，包结构不对" >> "$OUT/report.md"
  exit 1
fi

echo "验签..."
if codesign --verify --deep --verbose=2 "$VAPP" >> "$OUT/report.md" 2>&1; then
  echo "- 验签：通过" >> "$OUT/report.md"
else
  echo "- 验签：失败（见上面输出）" >> "$OUT/report.md"
  FAIL=1
fi

echo >> "$OUT/report.md"
echo '```' >> "$OUT/report.md"
codesign -dv "$VAPP" >> "$OUT/report.md" 2>&1 || true
echo '```' >> "$OUT/report.md"

if [ -f "$VAPP/embedded.mobileprovision" ]; then
  echo "- 描述文件：已装进包里" >> "$OUT/report.md"
else
  echo "- 描述文件：包里没有（临时签名时正常，真签名时不应该这样）" >> "$OUT/report.md"
fi

{
  echo "- 包大小：$(du -h "$IPA" | cut -f1)，SHA256：$(shasum -a 256 "$IPA" | cut -d' ' -f1)"
  echo
} >> "$OUT/report.md"

[ "$FAIL" = 0 ] || exit 1
