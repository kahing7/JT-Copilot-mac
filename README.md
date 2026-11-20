# JT Copilot

JT Copilot is a Windows desktop voice copilot. The current implementation is the
first vertical slice: a low-focus floating widget with a real global hold-to-talk
shortcut, microphone capture, live level feedback, local WAV persistence, and
basic settings.

## Current Status

Phase 1 is complete. The application does not yet include ASR, LLM analysis, or
text insertion into the active application.

Implemented:

- .NET 10 WPF application using MVVM and dependency injection.
- Modular project boundaries for Domain, Contracts, Application, Infrastructure,
  and Desktop.
- Frameless floating widget with expand/collapse, drag, Topmost, and placement
  persistence.
- `Ctrl + Alt + Space` hold-to-talk global shortcut and `Esc` cancellation.
- Real microphone enumeration and 16 kHz mono WAV capture through NAudio.
- Local settings and recording storage.
- Settings window with microphone selection, shortcut display, Topmost control,
  and recording-folder access.
- Unit and persistence integration tests.

Not implemented yet:

- Speech recognition providers.
- AI thinking and suggestions.
- Focus validation and text insertion.
- SQLite task history.
- Light theme, startup registration, installer, update channel, and code signing.

## Requirements

- Windows 11 x64
- .NET SDK 10.0.402 or compatible .NET 10 SDK
- A recording device visible to Windows

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

Hold `Ctrl + Alt + Space` to record, release to save, and press `Esc` while
recording to cancel. The settings action exposes the current microphone and the
recording directory.

## Local Data

Application data is stored under:

```text
%LOCALAPPDATA%\JT Copilot\
├── settings.json
└── recordings\
```

Recordings are not uploaded in Phase 1. Logs must not contain passwords, API keys,
full transcripts, or document contents.

## Publish

```powershell
dotnet publish src/JT.Copilot.Desktop/JT.Copilot.Desktop.csproj `
  -c Release `
  -r win-x64 `
  --self-contained false `
  -o artifacts/publish/phase1
```

## Documentation

- [Product and technical specification](PROJECT_SPEC.md)
- [Architecture](docs/architecture.md)
- [Decisions](docs/decisions.md)
- [Compatibility matrix](docs/compatibility-matrix.md)
- [Phase 1 validation](docs/phase1-validation.md)
