# Decisions

## ADR-001: Use A Modular WPF Monolith

- Status: Accepted
- Date: 2026-11-21
- Decision: Build Phase 1 as a .NET 10 WPF modular monolith with Domain,
  Application, Infrastructure, Contracts, and Desktop projects.
- Reason: The product is local and single-user in V1. Microservices or a web
  backend would add deployment and privacy cost without validating the core
  desktop workflow.

## ADR-002: Use Ctrl+Alt+Space For Hold-To-Talk

- Status: Superseded by ADR-007
- Date: 2026-11-21
- Decision: Use `Ctrl + Alt + Space` instead of `Alt + Space`.
- Reason: `Alt + Space` collides with the Windows window system menu and would
  break a common keyboard workflow.

## ADR-003: Use JSON Only For Phase 1 Preferences

- Status: Accepted
- Date: 2026-11-21
- Decision: Store window and microphone preferences in a local JSON file.
- Reason: Phase 1 has no task entities. SQLite and EF Core are deferred until the
  Task Engine introduces relational history.

## ADR-004: Keep The Floating Widget Non-Activating

- Status: Accepted
- Date: 2026-11-21
- Decision: Apply `WS_EX_NOACTIVATE` to the floating widget and use a separate
  keyboard-accessible settings window.
- Reason: Voice input must not change the foreground application or focus target.

## ADR-005: Capture 16 kHz Mono PCM WAV

- Status: Accepted
- Date: 2026-11-21
- Decision: Record WAV audio in 16 kHz, 16-bit, mono format.
- Reason: It is compact, broadly compatible with speech recognition services, and
  easy to validate independently of a future ASR choice.

## ADR-006: Keep Capture And AI State Separate

- Status: Accepted
- Date: 2026-11-21
- Decision: Phase 1 only models voice capture state. AI analysis will receive its
  own state machine and must run asynchronously after transcription.
- Reason: Combining write and analysis states in one enum makes parallel failures
  and retries ambiguous.

## ADR-007: Make The Hold-To-Talk Chord Configurable

- Status: Accepted
- Date: 2026-11-21
- Decision: Make the global chord editable in Settings and use
  `Ctrl+Shift+J+T` as the default.
- Reason: The user needs to avoid conflicts with their own applications, and the
  old read-only default was not adaptable.
- Tradeoff: A multi-key global chord is swallowed while the app is running. The
  settings window provides validation and a one-click default restore.
