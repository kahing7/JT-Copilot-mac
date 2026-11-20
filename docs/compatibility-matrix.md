# Compatibility Matrix

## Development Environment

| Item | Result | Evidence |
| --- | --- | --- |
| Windows 11 Pro x64 | Verified | Build `10.0.26300` |
| .NET SDK 10.0.402 | Verified | `dotnet --info` |
| Windows Desktop Runtime 10.0.13 | Verified | `dotnet --list-runtimes` |
| WPF template | Verified | `dotnet new list wpf` |
| Git | Verified | Installed at `C:\Program Files\Git\cmd\git.exe` |
| NuGet | Verified | `api.nuget.org` returned HTTP 200 |

## Audio Devices

The verification machine exposed two capture endpoints:

- Microphone Array (Intel Smart Sound Technology)
- Microphone (Realtek Audio)

The Realtek/Intel capture path produced a valid WAV in the Phase 1 validation
test. Device-specific ASR quality is not evaluated yet.

## Target Applications

The following applications are installed by the environment check:

- Feishu 8.6.13
- Microsoft Office 2016-style installation
- WPS Office
- Chrome
- Edge
- WeChat
- VS Code
- Windows Notepad

Phase 1 does not insert text, so application compatibility is not claimed. Phase 2
must validate focus and insertion behavior separately for every required target.

## Known Platform Limitations

- The current widget is Windows-only.
- Windows 10 and ARM64 are not part of the accepted Phase 1 matrix.
- Elevated target applications remain subject to Windows UIPI restrictions.
- The user account does not run as administrator.
