# JT Copilot · macOS

JT Copilot 的 macOS 原生版本，使用 Swift + SwiftUI + AppKit 重写。交互与 Windows 版保持一致：悬浮球启动、实时逐字写入当前编辑器、独立引导面板提示下一句，结束时由智谱校正并原位替换全文。

## 与 Windows 版的对应关系

| 能力 | Windows 版 | macOS 版 |
| --- | --- | --- |
| 界面 | WPF + MVVM | SwiftUI + AppKit 面板 |
| 实时识别 | Vosk 本地模型 | Apple Speech（系统语音识别） |
| 最终识别与优化 | 智谱 GLM-ASR-2512 + GLM-4.6 | 相同 |
| 全局快捷键 | 低级键盘钩子 | CGEventTap |
| 写入其他应用 | UI Automation + SendInput | Accessibility + CGEvent |
| 密钥存储 | DPAPI 文件 | macOS 钥匙串 |
| 模糊背景 | Acrylic | NSVisualEffectView |
| 单实例 | 命名 Mutex | 文件锁 |
| 业务逻辑 | C# | 按原逻辑移植为 Swift（术语纠正、模板引擎、Diff、合并） |

## 环境要求

- macOS 14 Sonoma 或更高
- Xcode 15+（或 Command Line Tools，包含 `swift`、`sips`、`iconutil`、`codesign`）
- 一个可用的麦克风
- 智谱 API Key（ASR 与 GLM 权限）

## 构建与运行

最省事的方式：双击 `安装到启动台.command`。它会编译应用、把 `JT Copilot.app` 安装到 `~/Applications`，刷新启动台并启动应用。

也可以在终端执行：

```bash
cd macos
bash scripts/build_app.sh
open "dist/JT Copilot.app"
```

或者直接安装到启动台：

```bash
cd macos
bash scripts/install_to_launchpad.sh
```

配置智谱 API Key：

1. 双击项目根目录的 `配置智谱Key.command`（会写入 macOS 钥匙串）；
2. 或者在启动应用前设置 `ZHIPU_API_KEY` 环境变量临时覆盖钥匙串配置。

API Key 配置不在应用设置窗口中维护。

如果启动后看不到界面：JT Copilot 是菜单栏/悬浮球应用，不会打开普通窗口。请看屏幕右下角的悬浮球，或菜单栏的波形图标；也可以运行项目根目录的 `诊断启动.command` 收集启动日志。

构建脚本会：

1. 用 SwiftPM 编译当前架构（需要 Intel + Apple Silicon 通用包时加 `UNIVERSAL=1`）；
2. 组装 `dist/JT Copilot.app`（含 Info.plist 与图标）；
3. 优先使用本机 Apple Development 证书签名；没有证书时回退到 ad-hoc 签名，并校验产物。

构建脚本会自动优先使用本机的 Apple Development 证书，避免每次重建后辅助功能授权失效。也可以显式指定签名身份：

```bash
CODESIGN_IDENTITY="Apple Development: 你的名字 (TEAMID)" bash scripts/build_app.sh
```

需要强制使用 ad-hoc 签名时传入 `CODESIGN_IDENTITY=-`。

也可以直接用 Xcode 打开 `macos/Package.swift` 阅读/编辑代码；但可运行产物请用上面的脚本生成，因为麦克风与语音识别权限依赖 `.app` 包中的 `Info.plist`。

## 首次启动与权限

首次启动会请求以下权限，也可以在“设置 → 系统权限”中逐项处理：

1. **麦克风**：录音；
2. **语音识别**：实时逐字预览；
3. **辅助功能**：全局快捷键，以及向其他应用写入/替换文字。

辅助功能授权后，如果快捷键仍不生效，请退出并重新启动应用。重建应用后若签名变化，可能需要在“系统设置 → 隐私与安全性 → 辅助功能”中重新勾选。

## 使用方式

1. 把光标放到飞书、Word、备忘录或任意可编辑文本中；
2. 同时按下 `⌃⇧J T`（Ctrl + Shift + J + T）开始；
3. 说话时会实时逐字写入，引导面板显示框架与“下一句”；
4. 按 `Esc` 结束，智谱会校正全文并原位替换；
5. 悬浮球右键菜单：设置、显示/隐藏引导面板、窗口置顶、退出；
6. 菜单栏图标也可打开设置、开始/结束写作或退出。

悬浮球可以自由拖动；引导面板默认固定在当前屏幕顶部居中，并支持拖动标题区域调整位置，半透明背景不会完全遮挡后方内容。

快捷键可以在设置中点击“修改”后重新录制，支持最多 4 个非修饰键同时按下，至少需要一个 Ctrl/Alt/Cmd 修饰键。

## 数据位置

```text
~/Library/Application Support/JT Copilot/
├── settings.json
└── recordings/
    └── recording-*.wav
```

智谱 API Key 存在 macOS 钥匙串中（service：`JT Copilot`，account：`zhipu-api-key`）。也支持通过环境变量 `ZHIPU_API_KEY` 临时覆盖。

录音仅在显式开始会话时进行；会话结束或取消后停止。

## 工程结构

```text
macos/
├── Package.swift
├── Sources/
│   ├── JTCopilotCore/          # 与平台无关的逻辑（可在 Linux 上运行测试）
│   │   ├── AppSettings.swift
│   │   ├── HotkeyGesture.swift
│   │   ├── DomainTermCorrector.swift
│   │   ├── DocumentFrameworkEngine.swift
│   │   ├── LiveTextDiff.swift
│   │   └── TranscriptMerger.swift
│   └── JTCopilot/              # macOS 应用
│       ├── main.swift / AppDelegate.swift / AppModel.swift
│       ├── AudioCaptureService.swift
│       ├── AppleSpeechRecognizer.swift
│       ├── HotkeyService.swift
│       ├── TextInsertionService.swift
│       ├── VoiceCaptureCoordinator.swift
│       ├── ZhipuClient.swift
│       ├── ZhipuApiKeyStore.swift
│       └── UI/
├── Tests/JTCopilotCoreTests/   # 术语纠正、模板引擎、Diff、设置、快捷键
├── Resources/Info.plist
├── Resources/AppIcon.png
└── scripts/build_app.sh
```

## 测试

核心逻辑不依赖 AppKit，可在任意装有 Swift 的机器上运行：

```bash
cd macos
swift test
```

当前覆盖：设置归一化与迁移、快捷键解析、术语纠正、模板检测与下一句推进、实时 Diff、转录重叠合并。

## 与 Windows 版的行为差异

- **实时识别引擎**：macOS 版使用 Apple Speech，不再下载 Vosk 模型；因此不需要模型目录，也没有 Vosk 的离线模型体积。若系统支持本地识别则优先离线；否则使用 Apple 的在线语音识别。最终文本仍由智谱重听每段音频校正。
- **快捷键**：默认仍是 Ctrl+Shift+J+T 同时按下，但 macOS 上对应 `⌃⇧J T`。需要辅助功能权限。
- **写入方式**：实时文字使用 Unicode 键盘事件；稳定段落与最终替换通过剪贴板粘贴。粘贴时会尽量保存并恢复原剪贴板内容，但无法保证恢复所有富文本类型。
- **密钥**：使用钥匙串，不写文件。
- **菜单位置**：额外提供菜单栏图标，便于在悬浮球移出屏幕后仍能打开设置或退出。

## 已知限制

- 飞书等 Electron 应用对 macOS Accessibility 的支持因版本而异；实时写入通常可用，最终原位替换失败时会保留优化结果供“复制结果”手动粘贴。
- 密码输入框会被拒绝写入。
- 若录制期间焦点离开原编辑器，实时与最终写入会暂停，并给出提示。
- 最终替换依赖会话文本仍位于光标之前且未被手工修改；校验失败时退回退格重输或提示复制。
- Apple Speech 需要网络或已下载的本地语音模型；不可用时自动回退到“智谱分片识别”，此时没有逐字预览，每段识别后整段写入。

## 故障排查

- **快捷键无反应**：检查辅助功能授权；确认没有其他应用占用同一组合键；重启应用。
- **没有声音/识别为空**：检查麦克风权限与设置中的麦克风设备；确认系统输入设备可用。
- **识别失败或未配置 Key**：运行 `配置智谱Key.command` 或设置 `ZHIPU_API_KEY`；检查网络。
- **最终没有替换原文**：多数是焦点或文本范围校验失败，可点击“复制结果”手动粘贴；也可查看引导面板中的提示。
- **重建后权限失效**：ad-hoc 签名每次重建都会变化；使用固定的 Apple Development 证书签名。
