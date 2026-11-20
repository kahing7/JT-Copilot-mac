# Compatibility Matrix

## Development Environment

| Item | Result | Evidence |
| --- | --- | --- |
| Windows 11 Pro x64 | Verified | Build `10.0.26300` |
| .NET SDK 10.0.402 | Verified | `dotnet --info` |
| Windows Desktop Runtime 10.0.13 | Verified | `dotnet --list-runtimes` |
| WPF and UI Automation | Verified | Build and Notepad UIA tests |
| Zhipu API key | Verified | ASR and GLM requests returned HTTP 200 |

## Editor Compatibility

| Target | Focus | Incremental Insert | Final Replace | Status |
| --- | --- | --- | --- | --- |
| Windows Notepad (`RichEditD2DPT`) | Verified | Verified | Verified | Supported |
| Feishu 8.6.13 | Installed, live doc not mutated | Database only | Not verified | Must be tested with a disposable document |
| Microsoft Word | Installed | Not verified | Not verified | Pending |
| Chrome / Edge | Installed | Not verified | Not verified | Pending |
| VS Code | Installed | Not verified | Not verified | Pending |
| WeChat | Installed | Not verified | Not verified | Pending |

## Verified Workflow

The full application coordinator was driven with a generated 14-second Chinese
speech sample:

- multiple overlapping ASR segments were recognized;
- stable text was inserted while Notepad retained existing text;
- guidance contained framework, directions, and next sentence;
- `Esc` triggered full consolidation and range replacement;
- final Notepad text preserved the original prefix and replaced only the session
  transcript.
- Vosk partial text was visible in Notepad before the sentence ended.
- Closing the guidance panel after round one and starting round two recreated it.

## Known Limitations

- ASR is segment-based near-real-time, not per-word.
- Feishu document replacement still requires manual compatibility validation
  because no disposable Feishu document was created during automated testing.
- Elevated target applications remain subject to Windows UIPI restrictions.
- Heavy custom editors may lack reliable UI Automation TextPattern ranges.
- Final replacement falls back to keyboard deletion and Unicode retyping when
  TextPattern is unavailable but the original window remains active.
