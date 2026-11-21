#!/bin/bash
cd "$(dirname "$0")/macos" || exit 1

bash scripts/install_to_launchpad.sh
status=$?

echo
if [[ $status -ne 0 ]]; then
    echo "安装失败。请检查上方错误信息，或在项目 GitHub Issues 中反馈。"
else
    echo "安装完成，JT Copilot 已放进启动台。"
fi
read -n 1 -s -r -p "按任意键关闭窗口..."
echo
