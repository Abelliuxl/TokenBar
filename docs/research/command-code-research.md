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

## Brand logo

The page uses the official Command Code mark from:

`https://commandcode.ai/logos/cmdsymbol-dark.svg`

The logo is a rounded-square frame containing the Command key symbol. The
vector paths are embedded in `BrandGlyphPaths` so the built-in provider does
not depend on a remote image at runtime.
