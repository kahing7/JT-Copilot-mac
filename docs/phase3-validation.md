# Phase 3 Validation

- Date: 2026-11-21
- Platform: Windows 11 Pro x64
- Local streaming ASR: Vosk `vosk-model-small-cn-0.22`
- Cloud ASR/editing: Zhipu `GLM-ASR-2512`, `GLM-4.6`

## Automated Tests

```text
Unit tests:        25 passed
Integration tests: 4 passed
Total:             29 passed
Build:             0 warnings / 0 errors
```

## Streaming Recognition

The generated Chinese speech sample produced continuously growing partials:

```text
我想
我想介绍
我想介绍一下
我想介绍一下这个产品
...
我想介绍一下这个产品它有三个核心能力第一个是实时识别第二个是自动写入
第三个是给用户一些提示让用户不要卡壳
```

The live insertion test verified that Notepad contained a partial transcript
before speech ended. New partials were applied through minimal Unicode diffs and
backspaces.

## Full Session

The complete Vosk + Zhipu coordinator flow then:

- produced side-panel framework and next-sentence guidance;
- waited for Zhipu segment reconciliation;
- consolidated raw ASR text with `GLM-4.6`;
- replaced the live transcript with:

```text
我想介绍一下这个产品，它有三个核心能力：第一个是实时识别，
第二个是自动写入，第三个是给用户一些提示，让用户不要卡壳。
```

## Guidance Panel Lifecycle

The round-one panel was closed manually. Starting round two recreated and displayed
the guidance panel successfully.

## Visual Validation

- Floating entry rendered as a `72 x 72` circular Acrylic orb.
- Context menu rendered without the default white WPF icon gutter.
- Orb and guidance opacity sliders persisted `35%`, `45%`, then restored `78%`,
  `68%`.
- Guidance panel rendered as a rounded translucent Acrylic surface.
- The published v0.3 single-file build loaded the local Vosk model and opened the
  guidance panel during a real session.

## Remaining Validation

- Feishu document insertion and final replacement still require a disposable live
  document test.
- Model performance should be measured on longer dictation and different CPUs.
- Vosk accuracy is intentionally supplemented by Zhipu final correction.
