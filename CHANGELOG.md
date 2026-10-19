# Changelog

All notable changes to TokenBar are documented here.

## [Unreleased] - 2026-10-19

### Fixed

- Custom-site balances no longer render as an empty progress bar when the page
  uses the fullwidth yuan sign (￥, U+FFE5). Units are now normalized before
  being compared, so ￥/¥, 元, CNY and RMB all resolve to the same currency, and
  `€`, `£` and ISO codes (HKD, SGD…) are recognized as money too.
- Balances in `credits`/`tokens` (or any non-currency unit) display as a plain
  amount instead of an empty bar. Real used/total windows still use a bar.
- `CustomProviderRuntime.numbers` no longer reads a fragment of an identifier
  as an amount (`abc123` used to yield `23`).

### Added

- Right-click a custom site → **重新选择字段…** re-picks its DOM/API field rule
  in place, keeping the entry's id, order and enabled state. Settings → 自定义
  站点 has the same action per row, plus inline rename.
- The candidate picker accepts an edited display name, so fields the page
  exposes no label for are no longer stuck with the generic "页面余额".
- `scripts/test.sh` builds the module and runs `tests/TokenBarTests` as an
  XCTest bundle; the custom-field path now has unit tests.

## [Unreleased] - 2026-10-02

- Command Code defaults to read-only CLI credentials and billing APIs, with
  selectable web login and automatic browser fallback.
- Missing Command Code quota rows retain their last known values with a stale
  marker; API failures no longer blank previously fetched quotas.
- Added executable Command Code checks including optional live API validation.

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
