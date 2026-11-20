# Phase 4 Validation

- Date: 2026-11-21
- Platform: Windows 11 Pro x64
- Local streaming ASR: Vosk `vosk-model-small-cn-0.22`
- Cloud ASR/editing: Zhipu `GLM-ASR-2512`, `GLM-4.5-Air`, `GLM-4.6`

## Automated Tests

```text
Unit tests:        44 passed
Integration tests: 5 passed
Total:             49 passed
Build:             0 warnings / 0 errors
```

## Domain Correction

The generated Vosk fixture contains:

```text
我们的CRM系统支持积分兑礼，OK吗？这个项目管理文档要先交代项目背景，再对齐业务目标
```

The corrected live transcript contains:

```text
我们的CRM系统支持积分兑礼，OK吗？这个项目管理文档要先交代项目背景，再对齐业务目标
```

The integration test specifically verifies that `新奥尔良系统`, `积分队里区`, and
the Vosk-confused `可以吗` form are corrected before insertion.

## Vocabulary Settings

The Settings window exposes a multiline business vocabulary field:

```text
CRM系统=新奥尔良系统,新奥良系统
积分兑礼=积分队里区,积分队里,积分兑换
OK=欧克,欧凯
```

Custom aliases are merged with built-ins and take precedence when an alias points
to a different standard term. The vocabulary is passed to the Zhipu ASR prompt and
reapplied after full-text optimization.

## Instant Guidance

The local framework engine is called on every corrected Vosk partial. The
project-management sequence is fixed and advances without waiting for Zhipu:

1. 先交代一下项目背景
2. 接下来对齐项目的业务目标
3. 说明项目范围和边界
4. 介绍项目规划和关键里程碑
5. 说明干系人与职责
6. 补充风险和依赖
7. 给出交付物和验收标准

The coordinator test uses a fake GLM response that tries to replace the next
sentence. The local prompt remains unchanged, while supplemental directions and
missing points are appended.

## Template Selection

The guidance panel exposes:

- 自动识别
- 项目管理文档
- PRD
- 周报
- 方案文档

The selected template is persisted in `%LOCALAPPDATA%\JT Copilot\settings.json`.
Auto mode detects project-management, PRD, weekly-report, and solution-document
terms.

## Window Smoke Test

The debug build was launched and inspected through Windows UI Automation:

- the floating `72 x 72` orb rendered at the saved desktop position;
- the context menu reopened the guidance panel;
- the template selector rendered readable labels and persisted Auto/Project
  Management selections;
- the Settings window exposed editable microphone, hotkey, API key, and business
  vocabulary controls.

## Remaining Validation

- Feishu still requires a disposable live-document insertion and replacement test.
- A real microphone pass should be repeated for the user's normal speaking rate.
- Recurring organization-specific names should be added to the vocabulary field.
