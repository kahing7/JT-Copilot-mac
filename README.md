# JT Copilot

JT Copilot is a Windows desktop writing assistant. It streams speech into the
current editor, keeps the text visible while the user is still speaking, and
maintains a separate non-activating panel with a framework and next-sentence
guidance. When the session ends, Zhipu consolidates the raw recognition segments
and replaces the session text with a corrected version.

## Current Status

The core workflow is implemented:

1. Press `Ctrl + Shift + J + T` to start.
2. Local Vosk recognition emits character/word-level partial hypotheses.
3. Business terms and English abbreviations are corrected locally before text is
   inserted.
4. Partial text is inserted immediately and revised with minimal backspace diffs.
5. A local document-template engine advances the next-sentence guidance instantly.
6. Zhipu only supplements directions and missing points; it cannot overwrite the
   local next sentence.
7. `Esc` stops capture.
8. Zhipu `GLM-ASR-2512` reconciles stable audio segments with vocabulary hints.
9. Zhipu `GLM-4.6` consolidates, deduplicates, and corrects the full session text.
10. Domain corrections are applied again before the optimized text replaces the
    live transcript.

Implemented:

- .NET 10 WPF modular application using MVVM and dependency injection.
- Configurable global shortcut, defaulting to `Ctrl + Shift + J + T`.
- Local Vosk Chinese streaming ASR with automatic first-use model download.
- 16 kHz mono microphone capture and local VAD segmentation.
- Unicode live typing with minimal backspace corrections.
- Local correction for `CRM`, `积分兑礼`, `OK`, common English abbreviations, and
  user-defined aliases.
- Editable business vocabulary in Settings using `standard=alias1,alias2`.
- Local template guidance for project-management documents, PRDs, weekly
  reports, solution documents, and auto-detection.
- The project-management prompt sequence advances through background, goals,
  scope, milestones, ownership, risks, and acceptance criteria without waiting
  for a network response.
- Zhipu ASR segment reconciliation and final full-text optimization.
- Acrylic `72 x 72` floating orb with adjustable opacity.
- Acrylic guidance panel with adjustable opacity.
- Dark context menu for Settings, guidance, Topmost, and Exit.
- UI Automation range replacement with keyboard fallback.
- DPAPI-protected Zhipu API key storage.

Current limitations:

- Partial text is input-method-like but may revise earlier words; it is not a
  guarantee of one fixed codepoint per time interval.
- Notepad insertion and final replacement are verified end to end.
- Feishu still requires a disposable live-document compatibility test.
- Vosk can still misrecognize arbitrary names. Add recurring terms to the
  business vocabulary; the built-in `OK` correction is deliberately limited to
  business-term context to avoid changing legitimate Chinese questions.
- Task history still does not use SQLite.

## Requirements

- Windows 11 x64
- .NET SDK 10.0.402 or compatible .NET 10 SDK
- A microphone visible to Windows
- A Zhipu API key with ASR and GLM access

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

Focus the target editor, place the cursor, press `Ctrl + Shift + J + T`, and
speak. Press `Esc` to finish.

Right-click the floating orb for Settings, guidance visibility, Topmost, and Exit.

## Local Data

```text
%LOCALAPPDATA%\JT Copilot\
├── settings.json
├── recordings\
├── secrets\
│   └── zhipu-api-key.bin
└── models\
    └── vosk-model-small-cn-0.22\
```

The Zhipu API key is DPAPI-protected for the current Windows user. Keys must not
be committed or logged.

## Publish

```powershell
dotnet publish src/JT.Copilot.Desktop/JT.Copilot.Desktop.csproj `
  -c Release `
  -r win-x64 `
  --self-contained true `
  -p:PublishSingleFile=true `
  -p:IncludeNativeLibrariesForSelfExtract=true `
  -o artifacts/publish/v0.4
```

## Documentation

- [Product and technical specification](PROJECT_SPEC.md)
- [Architecture](docs/architecture.md)
- [Decisions](docs/decisions.md)
- [Compatibility matrix](docs/compatibility-matrix.md)
- [Phase 1 validation](docs/phase1-validation.md)
- [Phase 2 validation](docs/phase2-validation.md)
- [Phase 3 validation](docs/phase3-validation.md)
- [Phase 4 validation](docs/phase4-validation.md)
