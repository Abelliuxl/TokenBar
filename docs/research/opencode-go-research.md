# opencode.go Research

> **Status:** Stub research file. The controller will replace this content with
> actual findings from a manual login via Chrome before the smoke-test step in
> Task 17. The placeholders below document the **expected** selectors so the
> JS in `OpenCodeGoAdapter.swift` is written assuming them.

## Source

- Entry URL: <https://opencode.ai/dashboard> (login wall appears first;
  user logs in, lands on dashboard).
- Quota widget location: top of dashboard, three cards labelled "5h",
  "week", "month".

## DOM (verified placeholders — to be confirmed by controller)

Each quota is rendered inside a card with `data-quota` attribute plus a
human-readable label inside the card body (e.g. "5h", "week", "month"):

```html
<div data-quota>
  <div class="label">5h</div>
  <div class="numbers">
    <span data-used>80</span>
    <span>/</span>
    <span data-total>500</span>
    <span class="unit">requests</span>
  </div>
</div>
```

## Selectors used by harvest script

| Field    | Selector                                  |
|----------|-------------------------------------------|
| card     | `[data-quota]` (find by textContent)      |
| used     | first child with `[data-used]`            |
| total    | first child with `[data-total]`           |

The harvest script searches for a `[data-quota]` card whose `.label` text
contains "5h" / "week" / "month" and pulls `data-used` / `data-total` text
content, both parsed as integers. It returns a JSON string like:

```
{"5h":{"used":80,"total":500},"week":{"used":...,"total":...},"month":{...}}
```

## XHR endpoints (placeholder — verify)

- None observed yet. If the dashboard later switches to a fetch-on-mount
  JSON endpoint (typical pattern), update `WebViewAdapter.parse` or
  introduce a custom URL-interceptor in `didFinish:`. For now, harvest
  happens entirely from the DOM.

## Notes for controller (manual smoke in Task 17)

1. Open Chrome, log into <https://opencode.ai>, reach the dashboard.
2. Open DevTools → Elements, locate the three quota cards.
3. Replace the placeholder selectors above with the verified ones.
4. Confirm the three labels — they may be uppercase ("5H") or longer
   ("5 hours", "weekly", "monthly"). Update the JS `pick(label)` calls
   in `OpenCodeGoAdapter.swift` to match.
5. (Optional) Network tab — watch for any `/api/...` requests whose
   response body contains the quota numbers; if so, capture them and
   consider switching from DOM harvest to fetch-intercept.
