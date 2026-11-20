#!/usr/bin/env bash
# 把这次运行的验证结果写进仓库的 docs/last-run.md，并提交。
# 小白话：跑完之后写一张“体检报告”存进仓库，下次不用进 Actions 也能看到上次跑得怎么样。
set -euo pipefail

OUT="${GITHUB_WORKSPACE:-$(pwd)}/out"
RUN_URL="https://github.com/${GITHUB_REPOSITORY}/actions/runs/${GITHUB_RUN_ID}"
mkdir -p docs
{
  echo "# IPA 签名验证报告"
  echo
  echo "- 运行：第 ${GITHUB_RUN_NUMBER} 次（${RUN_URL}）"
  echo "- 时间：$(date -u '+%Y-%m-%d %H:%M UTC')"
  echo "- 模式：${MODE:-adhoc}"
  echo "- 结果：${JOB_STATUS:-unknown}"
  echo
  if [ -f "$OUT/report.md" ]; then
    cat "$OUT/report.md"
  else
    echo "（没有验证记录：准备步骤没跑完）"
  fi
} > docs/last-run.md

git config user.name "ipa-signer-bot"
git config user.email "ipa-signer-bot@users.noreply.github.com"
git add docs/last-run.md
if git commit -m "验证报告：第 ${GITHUB_RUN_NUMBER} 次运行 [skip ci]"; then
  git push
else
  echo "报告没有变化，不用提交"
fi
