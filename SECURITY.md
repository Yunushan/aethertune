# Security Policy

## Supported versions

Only the latest commit on `main` and the latest published version tag are
actively maintained. Older builds may contain dependency or platform-security
issues and should be upgraded before handling real credentials or personal
listening data.

## Reporting a vulnerability

Use GitHub's private advisory form:

<https://github.com/Yunushan/aethertune/security/advisories/new>

If private reporting is unavailable, contact the maintainer through the
repository profile before disclosing details publicly. Do not open public
issues for vulnerabilities that expose user data, tokens, file paths, playback
history, or credentials.

Please include the affected version or commit, platform, reproduction steps,
impact, and whether a credential, local path, network request, or backup is
involved. The maintainer will acknowledge a report within five business days,
keep the report private while a fix is prepared, and publish a coordinated
advisory when disclosure is safe.

Do not open public issues for vulnerabilities that expose user data, tokens, file paths, playback history, or credentials.

## Security principles

- No telemetry by default.
- No provider credentials in preferences, library/queue JSON, logs, or backups.
- User-configured provider secrets use platform-secure storage and are deleted with the account.
- Credentialed providers require HTTPS by default; insecure HTTP needs explicit user consent.
- Authenticated request failures and runtime stream URLs must not expose secrets through persisted state or user-visible errors.
- Provider adapters must clearly document which network requests they perform.
- The core app must work without any online account.
- Release artifacts must not be described as store-ready until signing,
  notarization, installer validation, and platform smoke tests are complete.
