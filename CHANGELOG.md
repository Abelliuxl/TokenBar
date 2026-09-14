# Changelog

All notable changes to TokenBar are documented here.

## [Unreleased] - 2026-09-14

### Added

- Added two Codex fetch modes, both reading the backend behind the Codex web
  analytics page (`https://chatgpt.com/codex/cloud/settings/analytics#usage`):
  `Codex 登录态` (default) reuses the ChatGPT login Codex CLI already stored in
  `~/.codex/auth.json`, and `网页登录` calls the same endpoint from inside the
  logged-in WebKit session.
- Added `ProviderStatus.stale` so a transient refresh failure keeps the last
  successful quotas on screen instead of blanking the card.

### Changed

- Codex no longer scans `~/.codex/sessions/**/*.jsonl`: Codex stopped writing the
  `token_count` rate-limit events that scan depended on.
- Codex falls back from the CLI login to the web session when the local login is
  missing or rejected, and only reports a relogin error when neither works.
- WebView adapters retry navigation and expose configurable harvest delay, cache
  policy and request headers.
- Command Code harvests after navigation commit with a 90s timeout,
  cache-bypassing requests and 20 harvest attempts.

### Fixed

- A navigation timeout or WebView navigation failure no longer clears a
  provider's last known quotas.

### Verification

- `scripts/secret_scan.sh` passed.
- `scripts/build.sh` passed.
- `scripts/smoke.sh` passed for the build artifact.
- Codex usage decoded from a captured `wham/usage` body into `5小时` / `7天`
  percentage quotas, then fetched live in the running app:
  `[result] provider=codex status=ok quotas=2`.
- Web-session mode returns `needsRelogin` for an unauthenticated session, so the
  card offers the in-app login button.

## [Unreleased] - 2026-08-26

### Added

- Added Alibaba Bailian AccessKey balance support with separate AccessKey ID and AccessKey Secret fields.
- Added Command Code provider support and official API balance modes for supported providers.
- Added provider brand/icon coverage and expanded registry and UI tests for the newly integrated providers.

### Changed

- Made refresh controls observable and throttled Codex reads to avoid redundant refresh work.
- Improved provider balance parsing, including negative DeepSeek balances and API fallback handling.
- Kept credential fields interactive while users paste values across multiple fields.

### Fixed

- Protected the credential editor from transient popover dismissal when the user switches to another app to copy a second credential.
- Credential editing now temporarily uses application-defined popover behavior and restores transient behavior after save or cancel.

### Verification

- `scripts/secret_scan.sh` passed.
- `BUILD_NUMBER=42 ./scripts/build.sh` passed.
- `scripts/smoke.sh` passed for the build artifact.
- Installed `/Applications/TokenBar.app` (v0.3.0 build 42) passed startup, code-signature, and clean-exit checks.
