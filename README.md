# JT Copilot

JT Copilot is a Windows desktop writing assistant. It listens to continuous
speech, inserts stable transcript segments at the active cursor, and updates a
separate non-activating panel with a live framework and next-sentence guidance.
When the session ends, it consolidates the full transcript, corrects errors, and
replaces the text written during that session.

## Current Status

The core voice-writing workflow is implemented and usable:

`Ctrl + Shift + J + T` starts a session, speech is segmented in real time, and
`Esc` finishes the session and triggers full-text optimization.

Implemented:

- .NET 10 WPF modular application using MVVM and dependency injection.
- Configurable global shortcut, defaulting to `Ctrl + Shift + J + T`.
- 16 kHz mono microphone capture and local VAD-based segmentation.
- Zhipu `GLM-ASR-2512` transcription for each stable audio segment.
- Incremental insertion of stable text into the original focused editor.
- Parallel Zhipu `GLM-4.5-Air` guidance with framework, next sentence, directions,
  and missing points.
- Non-activating side panel for live guidance.
- Final `GLM-4.6` consolidation and correction of all raw ASR segments.
- UI Automation range tracking and one-step clipboard-based replacement.
- Safe fallback when focus or text range cannot be verified.
- DPAPI-protected local API key storage.

Current limitations:

- Recognition is segment-based near-real-time, not word-by-word transcription.
- Notepad insertion and final replacement are verified end to end.
- Feishu is the primary target but still requires a live document compatibility
  test; unsupported editors fall back to showing the optimized text for manual
  copy.
- Task history uses no SQLite database yet.
- Light theme, startup registration, installer signing, and auto-update are not
  included.

## Requirements

- Windows 11 x64
- .NET SDK 10.0.402 or compatible .NET 10 SDK
- A microphone visible to Windows
- A valid Zhipu API key with ASR and GLM access

## Build And Test

```powershell
dotnet restore JT.Copilot.slnx
dotnet build JT.Copilot.slnx
dotnet test JT.Copilot.slnx
```

## Run

```powershell
dotnet run --project src/JT.Copilot.Desktop/JT.Copilot.Desktop.csproj
```

Usage:

1. Focus the target editor and place the cursor.
2. Press `Ctrl + Shift + J + T` once to start.
3. Stable speech segments are inserted while the side panel updates.
4. Press `Esc` to finish and optimize the full session text.

The API key can be entered in Settings and is encrypted with Windows DPAPI.

## Local Data

```text
%LOCALAPPDATA%\JT Copilot\
├── settings.json
├── recordings\
└── secrets\
    └── zhipu-api-key.bin
```

The API key file is DPAPI-protected for the current Windows user. Keys must never
be committed to the repository or written to logs.

## Publish

```powershell
dotnet publish src/JT.Copilot.Desktop/JT.Copilot.Desktop.csproj `
  -c Release `
  -r win-x64 `
  --self-contained true `
  -p:PublishSingleFile=true `
  -p:IncludeNativeLibrariesForSelfExtract=true `
  -o artifacts/publish/v0.2
```

## Documentation

- [Product and technical specification](PROJECT_SPEC.md)
- [Architecture](docs/architecture.md)
- [Decisions](docs/decisions.md)
- [Compatibility matrix](docs/compatibility-matrix.md)
- [Phase 1 validation](docs/phase1-validation.md)
- [Phase 2 validation](docs/phase2-validation.md)
