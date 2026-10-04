#!/bin/bash
# =============================================================================
# 一键安装到 iPad：下载题库 → 生成 Xcode 工程 → 编译 → 安装并打开。
#
# 用法（在仓库根目录运行）:
#   ./scripts/install-ipad.sh [--team <Team ID>] [--bundle-id <Bundle ID>] [--device <设备 ID>] [--skip-content]
#
# 需要：macOS、Xcode（已登录 Apple ID）、用数据线连接并已信任这台 Mac 的 iPad（打开开发者模式）。
# 免费 Apple ID 签名的 App 7 天后过期，重新运行本脚本即可续期，练习记录不会丢失。
# =============================================================================
set -euo pipefail
cd "$(dirname "$0")/.."

CONTENT_REPO="https://github.com/Gordonynh/ielts-cd-practice-content.git"
PROJECT="IELTSCDPractice.xcodeproj"
SCHEME="IELTSCDPractice"
DERIVED="$HOME/Library/Developer/Xcode/DerivedData/IELTSCDPractice"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

TEAM=""
BUNDLE_ID=""
DEVICE=""
SKIP_CONTENT=0
while [ $# -gt 0 ]; do
    case "$1" in
        --team) TEAM="$2"; shift 2 ;;
        --bundle-id) BUNDLE_ID="$2"; shift 2 ;;
        --device) DEVICE="$2"; shift 2 ;;
        --skip-content) SKIP_CONTENT=1; shift ;;
        -h|--help) sed -n '2,11p' "$0"; exit 0 ;;
        *) echo "未知参数：$1" >&2; exit 2 ;;
    esac
done

step() { printf '\n==> %s\n' "$1"; }
fail() { printf '\n✗ %s\n' "$1" >&2; exit 1; }

# -----------------------------------------------------------------------------
step "1/6 检查开发工具"
command -v xcodebuild >/dev/null || fail "没有找到 Xcode。请从 App Store 安装 Xcode，打开一次并完成组件安装后重试。"
xcode-select -p | grep -q "\.app/Contents/Developer" \
    || fail "命令行工具没有指向 Xcode。请运行：sudo xcode-select -s /Applications/Xcode.app/Contents/Developer"
xcodebuild -version | head -1
command -v python3 >/dev/null || fail "没有找到 python3（安装 Xcode 命令行工具后自带）。"
command -v git >/dev/null || fail "没有找到 git（安装 Xcode 命令行工具后自带）。"

# -----------------------------------------------------------------------------
step "2/6 准备题库"
BANK="IELTSCDPractice/Content/bank"
if [ "$SKIP_CONTENT" = 1 ]; then
    echo "跳过（--skip-content）"
elif [ -d content/.git ]; then
    git -C content pull --ff-only
    rsync -a --delete content/bank/ "$BANK/"
elif [ -f "$BANK/index.json" ]; then
    echo "已有题库（$BANK），不覆盖。"
else
    git clone --depth 1 "$CONTENT_REPO" content
    rsync -a --delete content/bank/ "$BANK/"
fi
[ -f "$BANK/index.json" ] && echo "题库：$(du -sh "$BANK" | cut -f1)" || echo "未安装题库，App 中的题目列表会是空的。"

# -----------------------------------------------------------------------------
step "3/6 确定签名团队"
if [ -z "$TEAM" ] && [ -f signing.local.json ]; then
    TEAM=$(python3 -c 'import json; print(json.load(open("signing.local.json")).get("team", ""))')
fi
if [ -z "$TEAM" ]; then
    # Xcode「设置 → 账户」中登录的 Apple ID 对应的团队
    TEAM=$(defaults read com.apple.dt.Xcode IDEProvisioningTeamByIdentifier 2>/dev/null \
        | sed -nE 's/.*teamID = "?([A-Z0-9]{10})"?;.*/\1/p' | head -1 || true)
fi
if [ -z "$TEAM" ]; then
    # 已有的 Apple Development 证书（OU 字段就是团队 ID）
    TEAM=$(security find-certificate -c "Apple Development" -p 2>/dev/null \
        | openssl x509 -noout -subject 2>/dev/null | sed -nE 's/.*OU ?= ?([A-Z0-9]{10}).*/\1/p' || true)
fi
[ -n "$TEAM" ] || fail "没有找到可用的 Apple ID。请打开 Xcode →「设置」→「账户」，点左下角 + 登录 Apple ID（免费账号即可），然后重新运行本脚本。"
echo "团队 ID：$TEAM"

# -----------------------------------------------------------------------------
step "4/6 查找 iPad"
xcrun devicectl list devices --json-output "$WORK/devices.json" >/dev/null 2>&1 || true
DEVICE_INFO=$(python3 - "$WORK/devices.json" "$DEVICE" <<'PY'
import json, sys
path, wanted = sys.argv[1], sys.argv[2]
try:
    devices = json.load(open(path))["result"]["devices"]
except Exception:
    devices = []
pads = []
for d in devices:
    hw, conn, props = d.get("hardwareProperties", {}), d.get("connectionProperties", {}), d.get("deviceProperties", {})
    if conn.get("transportType") == "sameMachine":  # 模拟器
        continue
    if wanted and wanted not in (d.get("identifier"), hw.get("udid")):
        continue
    if not wanted and hw.get("deviceType") != "iPad":
        continue
    pads.append((conn.get("tunnelState") == "connected", d["identifier"], hw.get("udid", ""),
                 props.get("name", "iPad"), props.get("developerModeStatus", ""), conn.get("pairingState", "")))
pads.sort(reverse=True)
if pads:
    _, ident, udid, name, dev_mode, pairing = pads[0]
    print("\t".join([ident, udid, name, dev_mode, pairing]))
PY
)
[ -n "$DEVICE_INFO" ] || fail "没有找到 iPad。请用数据线连接 iPad 并解锁，在 iPad 上点「信任此电脑」，然后重新运行本脚本。"
IFS=$'\t' read -r DEVICE_ID DEVICE_UDID DEVICE_NAME DEV_MODE PAIRING <<< "$DEVICE_INFO"
echo "设备：$DEVICE_NAME（$DEVICE_UDID）"
[ "$PAIRING" = "paired" ] || fail "iPad 还没有与这台 Mac 配对。请解锁 iPad，在弹出的提示中点「信任」，然后重新运行。"
if [ "$DEV_MODE" = "disabled" ]; then
    fail "iPad 没有打开开发者模式。请在 iPad「设置 → 隐私与安全性 → 开发者模式」中打开，按提示重启并确认，然后重新运行。"
fi

# -----------------------------------------------------------------------------
step "5/6 生成工程并编译（第一次约需几分钟）"
if [ -n "$BUNDLE_ID" ]; then
    python3 scripts/generate-xcodeproj.py --team "$TEAM" --bundle-id "$BUNDLE_ID"
else
    python3 scripts/generate-xcodeproj.py --team "$TEAM"
fi
BUNDLE_ID=$(python3 -c 'import json; print(json.load(open("signing.local.json"))["bundleID"])')
if ! xcodebuild -project "$PROJECT" -scheme "$SCHEME" -configuration Release \
        -destination "platform=iOS,id=$DEVICE_UDID" -derivedDataPath "$DERIVED" \
        -allowProvisioningUpdates -allowProvisioningDeviceRegistration build > "$WORK/build.log" 2>&1; then
    grep -E "error:|Signing|provision" "$WORK/build.log" | sort -u | head -20 >&2 || true
    fail "编译失败。若提示签名或描述文件问题：确认 Xcode「设置 → 账户」已登录 Apple ID；若 Bundle ID 被占用，加 --bundle-id com.<你的名字>.ieltscdpractice 重新运行。"
fi
APP="$DERIVED/Build/Products/Release-iphoneos/IELTS CD Practice.app"
[ -d "$APP" ] || fail "没有找到编译好的 App：$APP"
echo "编译完成"

# -----------------------------------------------------------------------------
step "6/6 安装到 iPad"
xcrun devicectl device install app --device "$DEVICE_ID" "$APP" > "$WORK/install.log" 2>&1 \
    || { tail -5 "$WORK/install.log" >&2; fail "安装失败。请确认 iPad 已解锁并保持连接后重试。"; }
if xcrun devicectl device process launch --device "$DEVICE_ID" --terminate-existing "$BUNDLE_ID" > "$WORK/launch.log" 2>&1; then
    printf '\n✓ 已安装并打开「IELTS CD Practice」。\n'
else
    printf '\n✓ 已安装。第一次打开前需要信任开发者：\n'
    printf '  iPad「设置 → 通用 → VPN 与设备管理」→ 选择你的 Apple ID → 信任，然后点主屏幕上的 App 图标。\n'
fi
printf '  使用免费 Apple ID 时，App 7 天后需要重新运行本脚本续期（数据不会丢失）。\n'
