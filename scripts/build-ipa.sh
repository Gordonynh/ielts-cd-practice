#!/bin/bash
# =============================================================================
# 打包未签名的 IPA（含题库），供 Sideloadly、AltStore 等工具用使用者自己的 Apple ID 签名安装。
#
# 用法（在仓库根目录运行）:
#   ./scripts/build-ipa.sh
#
# 输出：build/IELTS-CD-Practice-<版本>.ipa
# 题库：使用 IELTSCDPractice/Content/bank/；没有时先从题库仓库下载。
# =============================================================================
set -euo pipefail
cd "$(dirname "$0")/.."

CONTENT_REPO="https://github.com/Gordonynh/ielts-cd-practice-content.git"
BANK="IELTSCDPractice/Content/bank"
DERIVED="$HOME/Library/Developer/Xcode/DerivedData/IELTSCDPractice-ipa"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

if [ ! -f "$BANK/index.json" ]; then
    echo "==> 下载题库"
    [ -d content/.git ] || git clone --depth 1 "$CONTENT_REPO" content
    rsync -a --delete content/bank/ "$BANK/"
fi

# 项目放在 iCloud 同步的目录时，iCloud 可能生成「xxx 2.png」这样的冲突副本，打包前清掉
find "$BANK" -name '* [0-9].*' -type f -delete

echo "==> 编译（Release，不签名）"
python3 scripts/generate-xcodeproj.py > /dev/null
# 命令行设置覆盖本地签名配置：IPA 不带个人团队和 Bundle ID，由安装工具重新签名
xcodebuild -project IELTSCDPractice.xcodeproj -scheme IELTSCDPractice -configuration Release \
    -destination 'generic/platform=iOS' -derivedDataPath "$DERIVED" \
    PRODUCT_BUNDLE_IDENTIFIER=com.ieltscdpractice.app DEVELOPMENT_TEAM= \
    CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY= \
    build > "$WORK/build.log" 2>&1 || { grep -E "error:" "$WORK/build.log" | sort -u | head -20 >&2; exit 1; }

APP="$DERIVED/Build/Products/Release-iphoneos/IELTS CD Practice.app"
VERSION=$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' "$APP/Info.plist")

echo "==> 打包"
mkdir -p "$WORK/Payload" build
# 在临时目录中打包，避免 iCloud 同步目录的扩展属性进入 IPA
ditto --norsrc --noextattr "$APP" "$WORK/Payload/IELTS CD Practice.app"
(cd "$WORK" && zip -qry -X "IELTS-CD-Practice.ipa" Payload)
OUT="build/IELTS-CD-Practice-$VERSION.ipa"
mv "$WORK/IELTS-CD-Practice.ipa" "$OUT"
echo "已生成 $OUT（$(du -h "$OUT" | cut -f1)）"
