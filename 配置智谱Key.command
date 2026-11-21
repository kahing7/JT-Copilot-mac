#!/bin/bash
set -euo pipefail

APP="$HOME/Applications/JT Copilot.app"
KEY="${ZHIPU_API_KEY:-}"

if [[ -z "$KEY" ]]; then
    read -r -s -p "请输入智谱 API Key（输入不会显示）: " KEY
    echo
fi

if [[ -z "$KEY" ]]; then
    echo "未输入 API Key，已取消。" >&2
    exit 1
fi

trap 'unset KEY' EXIT
echo "==> 写入 macOS 钥匙串"

if [[ -d "$APP" ]]; then
    security add-generic-password \
        -U \
        -s "JT Copilot" \
        -a "zhipu-api-key" \
        -w "$KEY" \
        -T "$APP" >/dev/null
else
    security add-generic-password \
        -U \
        -s "JT Copilot" \
        -a "zhipu-api-key" \
        -w "$KEY" >/dev/null
fi

echo "智谱 API Key 已写入钥匙串（service: JT Copilot，account: zhipu-api-key）。"
echo "如果 JT Copilot 已经在运行，请退出后重新打开。"

read -n 1 -s -r -p "按任意键关闭窗口..."
echo
