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

## ADR-015: Correct Domain Vocabulary Before Live Insertion

- Status: Accepted
- Date: 2026-11-21
- Decision: Apply built-in and user-defined domain aliases to Vosk partials,
  Zhipu segments, and final optimized text before insertion or replacement.
- Reason: Waiting for the final cloud pass leaves recurring errors visible during
  dictation. Local aliases make the inserted text stable immediately.
- Tradeoff: Aliases can be over-applied, so the built-in `可以吗` to `OK吗` rule is
  limited to known business terms and users can edit their own vocabulary.

## ADR-016: Make Local Templates Authoritative For Next-Sentence Guidance

- Status: Superseded for macOS by ADR-020; retained on Windows
- Date: 2026-11-21
- Decision: Build framework and next-sentence guidance locally on every corrected
  partial; allow GLM to add only directions and missing points.
- Reason: Network latency caused long pauses at exactly the moment the user needed
  the next prompt.
- Tradeoff: Built-in templates need explicit maintenance, while LLM output is
  intentionally prevented from changing the primary prompt.

## ADR-017: Persist The Selected Document Template

- Status: Accepted
- Date: 2026-11-21
- Decision: Persist an Auto/ProjectManagement/PRD/WeeklyReport/Solution template
  selection in app settings and expose it in the guidance panel.
- Reason: Users often dictate recurring document types and should not need to
  select the framework every session.

## ADR-018: Follow The Pointer With The Guidance Panel

- Status: Accepted
- Date: 2026-11-21
- Decision: Keep the guidance panel to the right of the pointer with a fixed gap,
  vertically centered on the pointer, and update its position while visible.
  Flip to the pointer's left side when the panel would leave the active monitor.
- Reason: Guidance should stay close to the work location without covering the
  pointer or forcing the user to manually reposition the panel for every task.

## ADR-019: Configure Zhipu Credentials Outside The Settings Window

- Status: Accepted
- Date: 2026-11-21
- Decision: Remove Zhipu API Key controls from the Settings window. Keep
  configuration in the existing environment-variable and OS-protected secret
  stores.
- Reason: Credential provisioning should not be coupled to the routine
  microphone, shortcut, and writing preferences UI.

## ADR-020: Infer The Document Type Before Choosing The Next Sentence

- Status: Accepted for macOS
- Date: 2026-11-21
- Decision: At each detected sentence boundary, send the just-completed sentence,
  full transcript, and current local framework to GLM. Require it to infer the
  document type first, then return the matching framework and next-sentence
  prompt. Keep the local engine only as an immediate fallback.
- Reason: Users switch between project plans, meeting minutes, reports, and other
  document types without declaring the type in advance. A keyword stage machine
  can keep a stale template active and cannot adapt the prompt to current content.
- Tradeoff: Guidance now depends on network latency for its best result. The
  local fallback, request throttling, stage matching, and stale-response rejection
  keep the panel usable while a response is pending or unavailable.
- Follow-up: Guidance requests run through one serial worker instead of cancelling
  the in-flight request whenever speech changes. Missing keys are shown as local
  mode in the panel rather than silently pretending that GLM was used. Response
  decoding accepts arrays, delimited strings, and `answer`/`data` wrappers for
  framework-like fields. Meeting minutes prioritize business discussion over
  time/location metadata.

## ADR-021: Keep The Guidance Surface Compact And Opacity-Coupled

- Status: Accepted for macOS
- Date: 2026-11-21
- Decision: Prefer a compact two-hundred-sixty-point-high guidance panel focused
  on the next sentence and current framework. Apply the guidance opacity setting
  to inner content surfaces as well as the outer frosted background.
- Reason: The previous panel occupied too much screen space and its inner cards
  stayed visually opaque while the outer surface faded, making the setting look
  broken and reducing access to the editor behind it.

## ADR-022: Use Screen-Coordinate Drag Areas For Borderless Windows

- Status: Accepted for macOS
- Date: 2026-11-21
- Decision: Place the shared AppKit drag probe above non-interactive header
  content and use native `performDrag(with:)` for guidance and settings headers.
- Reason: The borderless settings panel did not move reliably with local SwiftUI
  translation values. Screen-coordinate deltas match the existing guidance-window
  behavior, while native drag prevents tracking loss on non-activating panels.

## ADR-023: Treat Full-Text Cleanup As Repetition And Logic Repair

- Status: Accepted for macOS
- Date: 2026-11-21
- Decision: During final consolidation, remove filler words, self-repetition,
  duplicated clauses, false starts, and clearly incoherent phrasing while
  preserving facts, names, numbers, and business conclusions. Show an explicit
  loading state in the guidance panel while the model runs.
- Reason: Speech transcripts frequently contain phrases such as "那个那个",
  repeated starts, and restated clauses. Punctuation-only cleanup leaves the
  final document visibly spoken and hard to use.

## ADR-024: Closing Guidance Ends The Session Before Optimization

- Status: Accepted for macOS
- Date: 2026-11-21
- Decision: While recording, the guidance close button ends the complete session,
  keeps the panel visible during processing, and then runs one full-transcript
  optimization. Sentence-boundary model calls are guidance only and never optimize
  or replace accumulated text.
- Reason: Hiding the panel without ending the session leaves the user unsure
  whether optimization ran, while per-sentence optimization can replace only the
  latest text and discard the accumulated document context.

## ADR-025: Accumulate Apple Speech Hypotheses Across Request Restarts

- Status: Accepted for macOS
- Date: 2026-11-21
- Decision: Keep completed session text separate from the current Apple Speech
  hypothesis. Commit the current hypothesis at silence boundaries and again when
  finishing, and use the accumulated full text for optimization and replacement.
- Reason: Apple Speech frequently starts a new recognition request without
  emitting `isFinal`. Treating each new hypothesis as the session transcript made
  `finish` receive only the latest few characters even though several audio
  segments had already been recognized.

## ADR-026: Use Freeform Streaming For Next-Sentence Guidance

- Status: Accepted for macOS
- Date: 2026-11-21
- Decision: Replace template-driven next-sentence generation with a 180 ms
  debounced, cancelable freeform stream from the full session transcript.
  Generate framework and checklists in a separate follow-up request.
- Reason: The reference implementation produces a natural next sentence
  immediately and works across logs, reviews, meeting notes, emails, and other
  open-ended writing. Fixed stage prompts made the assistant sound like a template
  and could recommend the wrong section.
- Tradeoff: Network latency affects the first visible token, so the previous valid
  suggestion remains visible until the new stream begins.

## ADR-027: Preserve Guidance History And Use Native Continuous Controls

- Status: Accepted for macOS
- Date: 2026-11-21
- Decision: Record the last valid next-sentence guidance before a new streaming
  request replaces it, expose the deduplicated history in a scrollable area, and
  use an AppKit-backed continuous slider for guidance opacity. Disable
  window-background movement so only the title drag area moves the panel.
- Reason: SwiftUI drag gestures inside a non-activating borderless panel could
  receive the initial click without reliable continuous drag updates, and
  overwriting the current suggestion during streaming made earlier guidance
  disappear before the user finished speaking it.
- Verification: A synthesized AppKit mouse sequence confirms continuous value
  changes, history append/dedupe/limit behavior has focused unit tests, and the
  built app leaves zero `Software Cursor` windows on screen.
