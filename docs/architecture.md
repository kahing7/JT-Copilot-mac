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
