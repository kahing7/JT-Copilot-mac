# Security Policy

## Reporting a vulnerability

Please report security issues privately through GitHub Security Advisories for
this repository. Do not open a public issue containing an API key, access token,
recording, transcript, credential file, or other sensitive data.

## Credential handling

- Never commit `ZHIPU_API_KEY` or any other credential.
- macOS stores the key in Keychain. Run `bash "配置智谱Key.command"` from the
  repository root to configure it without writing the key into the repository.
- Windows reads `ZHIPU_API_KEY` first and otherwise uses the current user's
  DPAPI-protected key file.
- Treat any credential exposed in a screenshot, terminal log, issue, or commit
  as compromised and rotate it immediately.

## Supported versions

Security fixes are applied to the latest revision of `main`. Older revisions do
not receive separate maintenance guarantees.
