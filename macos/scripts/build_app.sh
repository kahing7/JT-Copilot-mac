#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

APP_NAME="JT Copilot"
EXECUTABLE="JTCopilot"
CONFIGURATION="${CONFIGURATION:-release}"
IDENTITY="${CODESIGN_IDENTITY:-}"
APP="$ROOT/dist/$APP_NAME.app"

# Prefer a stable local signing identity so macOS keeps permissions across
# rebuilds. Explicitly set CODESIGN_IDENTITY=- to force ad-hoc signing.
if [[ -z "$IDENTITY" ]]; then
    IDENTITY="$(
        security find-identity -v -p codesigning 2>/dev/null \
            | sed -n 's/.*"\(Apple Development: .*\)"$/\1/p' \
            | head -n 1
    )"
    IDENTITY="${IDENTITY:--}"
fi

if ! command -v swift >/dev/null 2>&1; then
    echo "未找到 swift。请先安装 Xcode 或 Command Line Tools。" >&2
    exit 1
fi

# 默认只构建当前架构，速度最快。
# 需要 Intel + Apple Silicon 通用包时：UNIVERSAL=1 bash scripts/build_app.sh
if [[ "${UNIVERSAL:-0}" == "1" ]]; then
    echo "==> 编译（通用二进制）"
    swift build -c "$CONFIGURATION" --arch arm64 --arch x86_64
    BIN_DIR="$(swift build -c "$CONFIGURATION" --arch arm64 --arch x86_64 --show-bin-path)"
else
    echo "==> 编译（当前架构）"
    swift build -c "$CONFIGURATION"
    BIN_DIR="$(swift build -c "$CONFIGURATION" --show-bin-path)"
fi

BIN="$BIN_DIR/$EXECUTABLE"

if [[ ! -f "$BIN" ]]; then
    echo "未找到构建产物：$BIN" >&2
    exit 1
fi

echo "==> 组装 .app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/$EXECUTABLE"
cp "$ROOT/Resources/Info.plist" "$APP/Contents/Info.plist"
printf 'APPL????' > "$APP/Contents/PkgInfo"

if [[ -f "$ROOT/Resources/AppIcon.png" ]]; then
    echo "==> 生成应用图标"
    ICONSET="$ROOT/.build/AppIcon.iconset"
    rm -rf "$ICONSET"
    mkdir -p "$ICONSET"
    for size in 16 32 128 256 512; do
        sips -z "$size" "$size" "$ROOT/Resources/AppIcon.png" \
            --out "$ICONSET/icon_${size}x${size}.png" >/dev/null
        sips -z "$((size * 2))" "$((size * 2))" "$ROOT/Resources/AppIcon.png" \
            --out "$ICONSET/icon_${size}x${size}@2x.png" >/dev/null
    done
    iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/AppIcon.icns"
    rm -rf "$ICONSET"
fi

echo "==> 签名（${IDENTITY}）"
xattr -cr "$APP" 2>/dev/null || true
codesign --force --deep --sign "$IDENTITY" "$APP"
codesign --verify --deep --strict "$APP"

echo
echo "构建完成：$APP"
echo "启动：open \"$APP\""
echo
echo "首次启动请在系统设置 → 隐私与安全性中允许："
echo "  麦克风 / 语音识别 / 辅助功能"
echo
if [[ "$IDENTITY" == "-" ]]; then
    echo "提示：当前使用 ad-hoc 签名，每次重新构建都可能需要在“辅助功能”中重新添加本应用。"
else
    echo "已使用稳定签名身份，后续重建通常会保留系统权限授权。"
fi
