# Security Policy

## Reporting a vulnerability

Please open a private security advisory on GitHub, or email the maintainer address listed in the repository profile once the project is published.

Do not open public issues for vulnerabilities that expose user data, tokens, file paths, playback history, or credentials.

## Security principles

- No telemetry by default.
- No account credentials stored by the core app.
- Provider adapters must use platform-secure storage for tokens.
- Provider adapters must clearly document which network requests they perform.
- The core app must work without any online account.
