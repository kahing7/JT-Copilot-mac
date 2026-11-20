# Architecture

## Goals

The first phase establishes a maintainable Windows desktop foundation without
pretending that future ASR, LLM, or text-writing capabilities are complete.

The design follows a modular monolith:

```text
Desktop (WPF, MVVM, window lifecycle)
    -> Infrastructure (Windows, audio, storage adapters)
    -> Application (orchestration and abstractions)
    -> Domain (state and value objects)
```

`Contracts` remains independent and is reserved for structured cross-boundary DTOs
that appear in later phases.

## Project Boundaries

| Project | Responsibility |
| --- | --- |
| `JT.Copilot.Domain` | Capture state, placement value object |
| `JT.Copilot.Contracts` | Future structured provider contracts |
| `JT.Copilot.Application` | Coordinator, settings model, provider interfaces |
| `JT.Copilot.Infrastructure` | NAudio capture, global keyboard hook, JSON storage |
| `JT.Copilot.Desktop` | WPF windows, resources, ViewModels, process lifecycle |

Dependencies point inward. Domain and Application do not reference WPF or Windows
specific adapters.

## Voice Capture State

Phase 1 uses a single capture state machine:

```text
Idle -> Recording -> Captured
  ^         |            |
  |         +-> Faulted  |
  +--------- Cancel <----+
```

The AI analysis channel will use a separate state machine in a later phase. It
must not be merged with recording or writing state, because those channels run
concurrently.

## Runtime Flow

```text
Low-level keyboard hook
    -> VoiceCaptureCoordinator
    -> IAudioCaptureService
    -> NAudio WaveIn
    -> WAV file
    -> UI state and level events
```

The low-level keyboard hook is installed on the WPF UI thread. Audio callbacks
arrive on NAudio worker threads and are marshalled to the UI dispatcher before
ViewModel updates.

## Window Behavior

The floating widget:

- is a frameless layered WPF window;
- uses fixed expanded and collapsed dimensions;
- is excluded from the taskbar and Alt+Tab;
- uses `WS_EX_NOACTIVATE` to avoid taking focus from the active work application;
- persists its position under `%LOCALAPPDATA%\JT Copilot\settings.json`;
- falls back to the lower-right work area if the saved position is off-screen.

The settings window is a normal keyboard-accessible dialog while the floating
widget remains intentionally non-activating.

## Data And Privacy

Phase 1 stores only UI settings and local WAV recordings. No content leaves the
machine. API keys are not implemented or persisted yet. Future cloud providers
must use Credential Manager or DPAPI and must not log request bodies or secrets.

## Error Handling

- Missing microphone: capture enters `Faulted`; the UI retains an actionable error.
- Hook installation failure: the application remains open with an error state.
- Invalid settings JSON: defaults are used and a warning is logged.
- Settings save failure: the UI remains usable and the error is logged.
- Settings window failure: the floating widget stays alive and reports the error.

## Next Architectural Boundary

Phase 2 adds:

- `ISpeechRecognitionProvider`;
- foreground window and focus snapshot;
- `ITextInsertionProvider`;
- target revalidation before any paste or input;
- clipboard preservation and explicit fallback behavior.
