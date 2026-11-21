#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

bash scripts/build_app.sh

DEST="$HOME/Applications"
mkdir -p "$DEST"

echo "==> 安装到启动台（${DEST}）"
rm -rf "$DEST/JT Copilot.app"
cp -R "$ROOT/dist/JT Copilot.app" "$DEST/"
xattr -dr com.apple.quarantine "$DEST/JT Copilot.app" 2>/dev/null || true

# 刷新启动台索引
killall Dock 2>/dev/null || true

echo
echo "已安装：$DEST/JT Copilot.app"
echo "打开启动台即可看到 JT Copilot。"
echo
echo "首次启动请在系统设置 → 隐私与安全性中允许："
echo "  麦克风 / 语音识别 / 辅助功能"
echo "智谱 API Key 请运行项目根目录的 配置智谱Key.command，或通过 ZHIPU_API_KEY 配置。"

open "$DEST/JT Copilot.app"
