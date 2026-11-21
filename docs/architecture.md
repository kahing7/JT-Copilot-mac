# Architecture

## Overview

JT Copilot is a local-first Windows desktop application built as a modular
monolith:

```text
Desktop (WPF, MVVM, windows)
    -> Infrastructure (audio, Windows automation, Zhipu clients, storage)
    -> Application (session coordination and provider abstractions)
    -> Domain (state and value objects)
```

`Contracts` remains reserved for structured cross-module DTOs.

## Session State

```text
Idle -> Recording -> Processing -> Completed
  ^         |            |
  |         +-> Faulted  |
  +--------- Cancel <----+
```

The user starts recording with the global shortcut and finishes with `Esc`.
Recording and guidance run concurrently; guidance never blocks text insertion.

## Audio Segmentation

NAudio captures 16 kHz, 16-bit, mono PCM. The coordinator buffers audio and
creates a segment when:

- speech has occurred and approximately 550 ms of silence follows; or
- continuous speech reaches approximately 3.8 seconds.

Each segment reuses the final 450 ms of the previous audio as overlap. Raw ASR
segments are retained for final consolidation so live boundary errors can be
corrected at session end.

## Speech Recognition

`ZhipuSpeechRecognitionProvider` sends each segment to:

```text
POST https://open.bigmodel.cn/api/paas/v4/audio/transcriptions
model=glm-asr-2512
stream=true
```

The API is file-oriented and returns SSE events. The provider reads the final
`transcript.text.done` event. This produces approximate rather than word-level
real-time recognition.

## Incremental Writing

At session start, `WindowsTextInsertionService` captures:

- foreground window handle;
- target process;
- focused UI Automation element;
- UI Automation TextPattern range at the insertion point.

Stable text is pasted through the clipboard after focus revalidation. Clipboard
content is backed up and restored. If focus changes, no text is sent.

## Guidance Channel

After each stable segment, `ZhipuWritingModelProvider` calls
`glm-4.5-air` with thinking disabled. It returns structured JSON containing:

- framework;
- next sentence;
- next directions;
- missing points.

Requests are debounced and previous analyses are cancelled. The non-activating
guidance window updates without taking focus.

## Final Consolidation

Pressing `Esc`:

1. stops capture and flushes the final segment;
2. waits for all queued ASR segments;
3. sends all raw segment texts to `glm-4.6` for overlap removal, deduplication,
   typo correction, grammar, and punctuation repair;
4. locates the exact text range written during this session;
5. verifies the current text still matches the session transcript;
6. replaces the selected range in one paste/undo unit.

If focus or range validation fails, the optimized text is kept in the side panel
for copy or manual replacement.

## Security And Privacy

- The API key is stored as DPAPI-protected bytes under `%LOCALAPPDATA%`.
- Keys are never written to source, settings JSON, documentation, or logs.
- Artifact names and truncated transcripts may be logged; full sensitive document
  contents must not be logged.
- Recording and transcription are active only during an explicit session.

## Remaining Architectural Risks

- Feishu document compatibility must be validated with a live document.
- Some editors expose neither reliable UIA TextPattern ranges nor stable focus.
- Segment boundaries may still introduce errors on highly technical vocabulary.
- The final replacement depends on the session text remaining unchanged.

## V0.3: Local Streaming Layer

`VoskStreamingSpeechRecognitionProvider` loads the Chinese Vosk model locally and
receives PCM continuously. It emits partial and final utterance hypotheses.

`WindowsTextInsertionService.UpdateLiveDraftAsync` computes the minimal common
prefix and applies only the required backspaces and Unicode characters. This
provides immediate input-method-like updates while avoiding a full document
rewrite on each partial.

Zhipu remains on the slower, higher-quality path:

- segment ASR for reconciliation;
- full-session consolidation with `GLM-4.6`;
- UIA range replacement or keyboard fallback.

The guidance panel uses a separate ViewModel-to-window lifecycle. Closing the panel
sets `IsGuidanceVisible` back to false so a subsequent session can create it again.

## V0.3: Acrylic Windows

The main window is a fixed `72 x 72` circular window. The guidance panel is a
rounded rectangle. Both use:

- `WS_EX_NOACTIVATE`;
- Windows Acrylic blur composition when available;
- a translucent graphite fallback;
- separate persisted opacity values;
- PerMonitorV2 DPI awareness.

## V0.4: Domain Correction And Instant Templates

Local Vosk partials now pass through `DomainTermCorrector` before insertion.
The corrector supports:

- built-in aliases for recurring Chinese ASR mistakes and English abbreviations;
- user-defined `standard=alias1,alias2` vocabulary;
- custom alias precedence over built-in aliases;
- a narrow business-context rule for Vosk confusing `OK吗` with `可以吗`.

The same corrector is applied to Zhipu segment text and the final optimized text.
Custom standards are also appended to the Zhipu ASR prompt as vocabulary hints.

`LocalDocumentFrameworkEngine` resolves Auto, project-management, PRD, weekly
report, solution, or general templates. It runs synchronously on every corrected
partial and updates:

- the complete framework;
- the next-sentence prompt;
- the current stage;
- a local direction and missing-point checklist.

The selected template is persisted in `settings.json` and can be changed from the
guidance panel. Auto mode detects the document type from recent transcript terms.

On the Windows path, GLM guidance remains a non-blocking supplement. A stale
request cannot replace the local framework or next sentence; only its directions
and missing points are merged when the local stage is unchanged.

## V0.5: Model-Inferred Guidance On macOS

The macOS guidance path keeps the local framework engine as an immediate
fallback, but GLM now owns the primary writing decision:

- infer the document type from the latest transcript instead of requiring the
  user to choose a template first;
- select the matching framework; meeting minutes use `会议主题 → 讨论要点 →
  结论与决策 → 行动项 → 待确认事项`, while time, location, and attendees remain
  secondary missing-point checks;
- return the complete framework and the next sentence to speak;
- replace the fallback prompt only when the response still matches the current
  local document stage.

Model requests are triggered at sentence boundaries: after approximately 550 ms
of silence, after the maximum segment length, or when Apple Speech emits a final
result. Partial hypotheses update the local fallback immediately but do not
request the model. The request includes the just-completed sentence, the full
transcript, and the current local framework.

A single worker owns all requests: a request in flight is never cancelled by the
next sentence, and only the latest pending transcript is sent next. A response
may update only the local framework stage that produced it. Guidance responses
accept either JSON arrays or delimited strings, and unwrap `answer` or `data`
objects, so a schema variation does not discard an otherwise usable next
sentence.

If no Zhipu key is available, the guidance header explicitly says that local
guidance is active. Local guidance continues to advance from transcript signals,
but it is not presented as a model-generated result.

The macOS guidance panel is a compact `820 x 260` surface. The next sentence and
current framework use primary text, while translucent inner cards multiply
their fill opacity by the guidance-opacity preference so they stay synchronized
with the outer panel.

The title bar uses an AppKit drag probe above non-interactive SwiftUI header
content and delegates to native `NSWindow.performDrag(with:)`. A diagnostic hit
test confirms that the top-center header resolves to the drag probe rather than
the SwiftUI hosting view.

## V0.6: Full-Text Cleanup And Loading State

At session completion, `glm-4.6` now explicitly removes spoken fillers,
self-repetition, duplicated clauses, false starts, and clearly incoherent
phrasing before using the result for in-place replacement. It may adjust
sentence order and transitions but may not add facts or expand the content.

While this pass runs, the guidance panel replaces the copy action with a small
progress indicator and the message "正在检查重复表达和逻辑衔接…". Key guidance
text uses white/high-contrast foregrounds so the next sentence, expandable
directions, and current framework remain readable over the translucent panel.

Closing the guidance panel while recording is an explicit session-end action:
it stops capture, keeps the panel visible in the processing state, and starts
full-text optimization exactly once. It must not merely hide the panel. Model
optimization is never called from sentence-boundary guidance updates.

Apple Speech can restart its recognition request without emitting a final result.
The macOS coordinator therefore keeps a `SessionTranscriptAccumulator` with
separate completed and current hypothesis text. At pauses and session end, the
current hypothesis is committed before optimization. Cumulative hypotheses that
already contain committed text are stripped rather than appended twice. This
prevents a later sentence from replacing the earlier document when no final event
was delivered.

## V0.7: Freeform Streaming Next Sentence On macOS

The macOS guidance path now follows the reference implementation used by the
Windows project:

- fixed template-stage prompts no longer determine the next sentence;
- every transcript change schedules a 180 ms debounced request;
- the full current transcript is sent directly to `glm-4.5-air` with `stream=true`;
- the first streamed text immediately replaces the current suggestion;
- a newer transcript cancels the stale stream and cannot overwrite newer text;
- framework, directions, and missing points are requested separately after the
  next sentence completes, so they never block guidance.

The previous valid suggestion remains visible until the replacement actually
starts streaming. Replaced suggestions are retained in session-scoped history.
