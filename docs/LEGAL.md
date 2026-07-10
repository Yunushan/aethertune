# Legal and Source Policy

AetherTune is designed as free/open-source music software, not as a piracy or circumvention tool.

## Allowed

- Playing files the user selects on their device.
- Connecting to user-owned servers.
- Connecting to public/open catalogs where streaming/downloading is permitted.
- Connecting to official APIs according to their terms.
- Caching/downloading only where the source allows it and `OfflineMediaPolicy` permits it from declared provider capabilities and disclosure.
- User-triggered metadata lookups through documented public APIs, with visible network disclosure and local source attribution.
- User-supplied credentials for user-owned servers, stored in the operating system credential vault and sent only after visible account configuration.

## Not allowed in this repository

- DRM bypass.
- Paid-service cloning.
- Credential theft.
- Private API scraping.
- Bundling copyrighted music without permission.
- Hiding network behavior from users.

## Why this matters

A project can be 100% free/open-source without copying proprietary services. Keeping the provider boundary clean protects users, contributors, and maintainers.

## External lyrics

AetherTune includes an adapter for LRCLIB's documented public search API but bundles no lyrics database or lyrics assets. Searches occur only after user action, and only a selected result is stored locally with provider attribution. Lyrics remain third-party content belonging to their respective rightsholders/providers; users and distributors are responsible for complying with applicable provider terms and local law.

## Self-hosted credentials

Jellyfin and Navidrome/Subsonic credentials belong to the user and their server. AetherTune stores secrets in platform-secure storage, excludes them from JSON backups, and requires HTTPS by default. Plain HTTP is available only after an explicit warning for LAN deployments; it does not provide transport confidentiality.
