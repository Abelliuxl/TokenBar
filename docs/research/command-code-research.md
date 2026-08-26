# Command Code Research

Provider: command code  
Usage URL: https://commandcode.ai/Abelliuxl/settings/usage

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

## API balance path

The Command Code CLI currently reads account credits from:

```text
GET https://api.commandcode.ai/alpha/billing/credits
Authorization: Bearer <Command Code API key>
```

Observed response shape:

```json
{
  "credits": {
    "monthlyCredits": 69.9411858041,
    "purchasedCredits": 0,
    "freeCredits": 0
  },
  "windowLimits": {
    "limited": true,
    "fiveHour": { "used": 0.0588141959, "cap": 14, "exceeded": false, "resetAt": 1787744320560 },
    "weekly": { "used": 0.0588141959, "cap": 35, "exceeded": false, "resetAt": 1788331120560 }
  }
}
```

TokenBar's API mode displays the three credit pools as USD balances and the
rolling windows as percentage quotas. The endpoint is not listed in the
published Provider API reference and lives under the undocumented `/alpha`
namespace, so the decoder is intentionally tolerant and the web-session mode
remains available as the default fallback.

## TokenBar dual-mode implementation

- `网页登录`: reuses the existing authenticated WebKit page session.
- `余额 API`: reads a user-provided Command Code API key from the local
  credential store and calls the credits endpoint directly without cookies.

## Brand logo

The page uses the official Command Code mark from:

`https://commandcode.ai/logos/cmdsymbol-dark.svg`

The logo is a rounded-square frame containing the Command key symbol. The
vector paths are embedded in `BrandGlyphPaths` so the built-in provider does
not depend on a remote image at runtime.
