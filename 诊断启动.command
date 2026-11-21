#!/bin/bash

APP="$HOME/Applications/JT Copilot.app"
BIN="$APP/Contents/MacOS/JTCopilot"

echo "=== 1. 检查安装 ==="
if [[ ! -d "$APP" ]]; then
    echo "没有找到：$APP"
    echo "请先双击运行 安装到启动台.command。"
    read -n 1 -s -r -p "按任意键关闭窗口..."
    echo
    exit 1
fi
ls -ld "$APP"

echo
echo "=== 2. 检查签名 ==="
if codesign --verify --deep --strict "$APP" 2>/tmp/jt-codesign.err; then
    echo "签名正常"
else
    echo "签名校验失败："
    cat /tmp/jt-codesign.err
fi

echo
echo "=== 3. 是否已有进程在运行 ==="
if pgrep -fl "JTCopilot" >/dev/null 2>&1; then
    echo "已有实例在运行："
    pgrep -fl "JTCopilot"
    echo
    echo "提示：悬浮球默认在屏幕右下角；也可以查看菜单栏的波形图标。"
    echo "如果需要重新启动，请先执行：killall JTCopilot"
else
    echo "没有正在运行的实例"
fi

echo
echo "=== 4. 保存的悬浮球位置 ==="
SETTINGS="$HOME/Library/Application Support/JT Copilot/settings.json"
if [[ -f "$SETTINGS" ]]; then
    cat "$SETTINGS"
else
    echo "还没有 settings.json（首次启动后会生成）"
fi

echo
echo "=== 5. 直接启动并收集输出（4 秒） ==="
pgrep -x "JTCopilot" >/dev/null 2>&1 && killall JTCopilot 2>/dev/null || true
sleep 1
LOG=/tmp/jtcopilot-launch.log
: > "$LOG"
if [[ ! -x "$BIN" ]]; then
    echo "可执行文件缺失：$BIN"
    read -n 1 -s -r -p "按任意键关闭窗口..."
    echo
    exit 1
fi

"$BIN" >"$LOG" 2>&1 &
PID=$!
sleep 4

if ps -p "$PID" >/dev/null 2>&1; then
    echo "进程已启动，PID=$PID"
    echo "悬浮球应出现在屏幕右下角，菜单栏应有波形图标。"
else
    echo "进程已退出（说明启动时崩溃或主动退出）。输出如下："
    cat "$LOG"
fi

echo
echo "=== 6. 最近的系统日志 ==="
log show --last 2m --style compact --predicate 'process == "JTCopilot"' 2>/dev/null | tail -40 || true

echo
read -n 1 -s -r -p "按任意键关闭窗口..."
echo
