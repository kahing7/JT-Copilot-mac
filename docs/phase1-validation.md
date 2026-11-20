# Phase 1 Validation

- Date: 2026-11-21
- Platform: Windows 11 Pro x64, build 10.0.26300
- Runtime: .NET 10.0.13

## Build

```text
dotnet build JT.Copilot.slnx
Build succeeded.
0 warnings
0 errors
```

## Tests

```text
dotnet test JT.Copilot.slnx
Unit tests:        10 passed
Integration tests: 1 passed
Total:             11 passed
```

Covered behavior:

- capture start and stop;
- audio provider failure mapping;
- cancellation returning to idle;
- finite and invalid window placements;
- settings normalization;
- JSON settings round-trip.

## Desktop Runtime

- WPF process remained responsive.
- Expanded widget rendered at `372 x 166` device-independent units.
- Window used `WS_EX_NOACTIVATE` and tool-window styles.
- Main window and controls were visible to Windows UI Automation.
- Expanded and collapsed bounds were verified as `372 x 166` and `72 x 72`.
- Settings dialog opened and closed without terminating the process.

## Real Audio Capture

The global shortcut was exercised with synthesized `Ctrl + Alt + Space` input.
The application recorded for approximately two seconds and produced:

```text
recording-20261121-002619-77c20627018747278461e65cd39c6fbd.wav
51,502 bytes
Approximate duration: 1.61 seconds
```

Windows `SoundPlayer` loaded the WAV successfully, confirming the file was a valid
playable WAV rather than a zero-byte placeholder.

Pressing `Esc` during a subsequent recording returned the UI to idle and removed
the temporary WAV, so the recording count did not increase.

## Published Executable

The Release build was published as a self-contained single-file Windows x64
executable:

```text
artifacts\publish\phase1\JT.Copilot.exe
140,926,770 bytes
```

The published executable launched successfully and created another valid WAV
through the same global hold-to-talk path.

## Remaining Limits

- No speech recognition or transcript is produced.
- No AI request or suggestion is produced.
- No text is inserted into another application.
- Light theme, startup registration, installer, signing, and auto-update remain
  deferred.
- Automated UI tests for layered WPF windows are not included in Phase 1.
