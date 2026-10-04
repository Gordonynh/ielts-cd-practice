#!/bin/bash
# =============================================================================
# 维护者使用：把本地生成的题库（IELTSCDPractice/Content/bank/）导出到题库仓库目录。
#
# 用法:
#   node scripts/build-bank.mjs && node scripts/build-extras.mjs
#   ./scripts/export-content.sh <题库仓库目录>
# =============================================================================
set -euo pipefail
cd "$(dirname "$0")/.."
DEST="${1:?用法：scripts/export-content.sh <题库仓库目录>}"
SOURCE="IELTSCDPractice/Content/bank"
[ -f "$SOURCE/index.json" ] || { echo "没有找到 $SOURCE/index.json，请先运行 build-bank.mjs 与 build-extras.mjs" >&2; exit 1; }
mkdir -p "$DEST/bank"
# 排除 iCloud 生成的冲突副本（「xxx 2.png」「index 2.json」）
rsync -a --delete --exclude '.DS_Store' --exclude '* [0-9].*' "$SOURCE/" "$DEST/bank/"
echo "已导出到 $DEST/bank（$(du -sh "$DEST/bank" | cut -f1)）"
