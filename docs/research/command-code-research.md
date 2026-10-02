# Command Code Research

Provider: command code  
Usage URL: https://commandcode.ai/Abelliuxl/settings/usage

## CLI API mode (verified 2026-10-02)

Default mode reads only `apiKey` from `~/.commandcode/auth.json`; it never
refreshes, rewrites or logs credentials. It uses the official CLI's
`https://api.commandcode.ai/alpha/whoami?limits=1` to determine organization
scope, then `billing/credits` and `billing/subscriptions` with the same orgId.
Requests include `User-Agent: command-code`; initial Python requests without
that header returned 403, while Swift URLSession requests with it succeeded.

- `windowLimits.fiveHour` / `weekly`: `used / cap * 100`, with epoch-ms `resetAt`.
- GOAT monthly: `(70 - credits.monthlyCredits) / 70 * 100`; requires an active
  `individual-goat` subscription and a valid `currentPeriodEnd`. Unknown plans
  omit monthly percentage rather than inventing a cap.
- `usage/summary.totalCost` is not the monthly credit decrement and is not used.
- Verified percentages 0.94 / 21.54 / 10.77 match the supplied webpage's rounded
  1 / 22 / 11. Reset timestamps are displayed in the Mac's local timezone;
  2026-10-26 16:28 UTC is October 27 00:28 in Asia/Shanghai.
- A missing key, failed API request or partial response falls back to WebKit.
  Partial snapshots preserve missing rows from the previous snapshot with an
  explicit stale marker. Failed reads retain previous quotas. No persistent
  quota cache or credentials migration is introduced.
- These are undocumented CLI endpoints; account revocation and upstream changes
  remain possible. The selectable web mode remains available.

Validation: `scripts/test-command-code.sh --live` covers percentage mapping,
timestamps, missing subscription, invalid numeric fields, unknown plans, stale
retention/recovery, and a real URLSession request returning all three windows.

## Observed usage structure

The authenticated page exposes three usage-limit progress bars:

| 页面标签 | DOM signal | TokenBar field |
|---|---|---|
| 5-Hour Limit | `[role="progressbar"]`, `aria-label="5-Hour Limit usage"`, `aria-valuenow="0"` | `fiveHour` |
| Weekly Limit | `[role="progressbar"]`, `aria-label="Weekly Limit usage"`, `aria-valuenow="0"` | `weekly` |
| Monthly Limit | `[role="progressbar"]`, `aria-label="Monthly Limit usage"`, `aria-valuenow="0"` | `monthly` |

`aria-valuenow` is the used percentage. The reset message is the `p` element
in the same quota row, for example `Resets in 4h 53m` or `Resets on Sep 26`.
The adapter uses the accessible role and ARIA value as its primary selectors,
with label and text fallbacks for locale or markup changes.

## Brand logo

The page uses the official Command Code mark from:

`https://commandcode.ai/logos/cmdsymbol-dark.svg`

The logo is a rounded-square frame containing the Command key symbol. The
vector paths are embedded in `BrandGlyphPaths` so the built-in provider does
not depend on a remote image at runtime.
