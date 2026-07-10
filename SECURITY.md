# Security Policy

## Reporting a vulnerability

Please open a private security advisory on GitHub, or email the maintainer address listed in the repository profile once the project is published.

Do not open public issues for vulnerabilities that expose user data, tokens, file paths, playback history, or credentials.

## Security principles

- No telemetry by default.
- No provider credentials in preferences, library/queue JSON, logs, or backups.
- User-configured provider secrets use platform-secure storage and are deleted with the account.
- Credentialed providers require HTTPS by default; insecure HTTP needs explicit user consent.
- Authenticated request failures and runtime stream URLs must not expose secrets through persisted state or user-visible errors.
- Provider adapters must clearly document which network requests they perform.
- The core app must work without any online account.
