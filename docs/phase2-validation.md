# Phase 2 Validation

- Date: 2026-11-21
- Platform: Windows 11 Pro x64
- Runtime: .NET 10
- Provider: Zhipu GLM-ASR-2512, GLM-4.5-Air, GLM-4.6

## Automated Tests

```text
Unit tests:        20 passed
Integration tests: 4 passed
Total:             24 passed
Build:             0 warnings / 0 errors
```

Coverage includes:

- shortcut parsing and migration;
- DPAPI secret round-trip without plaintext leakage;
- ASR SSE final-event parsing;
- GLM snake_case JSON fields;
- coordinator start, finish, cancel, and fault mapping;
- task settings persistence.

## Real Provider Checks

The Zhipu key authenticated successfully.

Generated Chinese speech:

```text
我想介绍一下这个产品，它有三个核心能力，第一个是实时识别，
第二个是自动写入，第三个是给用户一些提示让用户不要卡壳
```

`glm-asr-2512` returned the complete transcript correctly through SSE.

`glm-4.5-air` returned a live framework, next sentence, and expansion directions.

`glm-4.6` corrected ASR overlap, homophones, duplicates, grammar, and punctuation.

## End-To-End Notepad Validation

The real coordinator, Zhipu providers, clipboard insertion, UI Automation range
capture, and final replacement were exercised against Notepad.

Original content:

```text
原有内容：
```

Final content:

```text
原有内容：我想介绍一下这个产品。它有三个核心能力：第一个是实时识别，
第二个是自动写入，第三个是给用户一些提示，让用户不要卡壳。
```

Observed guidance:

```text
Framework: 产品介绍 | 核心功能 | 优势特点 | 应用场景
Next sentence: 首先，让我们详细了解一下实时识别功能。
```

The final replacement used UI Automation range selection and clipboard paste. The
manual document content outside the session remained unchanged.

## Remaining Validation

- Feishu document insertion and final replacement must be tested in a disposable
  online document before claiming full Feishu support.
- Microphone quality, long dictation sessions, network reconnect, and rate limits
  require continued manual testing.
