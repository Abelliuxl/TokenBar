# Changelog

All notable changes to TokenBar are documented here.

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
