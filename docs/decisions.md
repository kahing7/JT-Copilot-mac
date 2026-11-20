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

## ADR-008: Use Segmented Near-Real-Time ASR

- Status: Accepted
- Date: 2026-11-21
- Decision: Capture continuous PCM, split on silence or 3.8 seconds, and submit
  overlapping segments to `glm-asr-2512`.
- Reason: Zhipu's documented ASR endpoint accepts audio files and streams the
  result, not a continuous microphone WebSocket in a form validated for this
  product.
- Tradeoff: Text appears every few seconds rather than word by word. Final raw
  segments are consolidated to repair boundary errors.

## ADR-009: Store The API Key With DPAPI

- Status: Accepted
- Date: 2026-11-21
- Decision: Encrypt the Zhipu key with current-user DPAPI and store it under the
  application's local secrets directory.
- Reason: The key must not appear in source, JSON settings, logs, or Git.

## ADR-010: Use UIA Ranges For Final Replacement

- Status: Accepted
- Date: 2026-11-21
- Decision: Capture the insertion range at session start, validate it at session
  end, and replace only the text written during the session.
- Reason: Replacing the entire document would be destructive. Automatic
  replacement is skipped when the range cannot be verified.

## ADR-011: Split Fast Guidance And High-Quality Editing Models

- Status: Accepted
- Date: 2026-11-21
- Decision: Use `glm-4.5-air` with thinking disabled for live guidance and
  `glm-4.6` for final consolidation.
- Reason: Live suggestions need low latency, while final editing needs stronger
  duplicate removal and grammar correction.

## ADR-012: Add Local Vosk Streaming ASR

- Status: Accepted
- Date: 2026-11-21
- Decision: Use Vosk Chinese streaming recognition for immediate partial text,
  while retaining Zhipu for segment reconciliation and final editing.
- Reason: Zhipu's file-oriented ASR cannot provide word-level input partials.
- Tradeoff: The local model adds a one-time download and uses CPU resources.

## ADR-013: Use Acrylic Circular And Guidance Surfaces

- Status: Accepted
- Date: 2026-11-21
- Decision: Render the main entry as a 72 DIP translucent Acrylic orb and the
  guidance surface as a rounded Acrylic panel, each with independent opacity.
- Fallback: If Windows Acrylic composition is unavailable, retain the translucent
  graphite visual instead of failing to render.

## ADR-014: Use Unicode Diff Insertion For Live Text

- Status: Accepted
- Date: 2026-11-21
- Decision: For live Vosk partials, compute the common prefix and send only the
  required backspaces plus Unicode characters.
- Reason: Rewriting the full text or using UIA for every character is slow and
  incompatible with some custom editors.
