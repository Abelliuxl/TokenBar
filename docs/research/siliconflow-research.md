# SiliconFlow Research

Provider: 硅基流动 (SiliconFlow)
Login URL: https://cloud.siliconflow.cn

## Pending investigation (fill in before smoke test)

- Console URL once logged in (e.g. https://cloud.siliconflow.cn/bills)
- Exact cookie name(s) issued on successful login
- Confirmed balance endpoint and its auth scheme (cookie vs Authorization header)
- Response JSON shape for `GET /api/v1/bills/balance`
- Units returned (CNY? fen?)
- Refresh cadence (any `Cache-Control` / `Expires` hints)
- Error shape when cookie is missing or expired

## Tentative parsing strategy

Assume:

```http
GET /api/v1/bills/balance HTTP/1.1
Host: cloud.siliconflow.cn
Cookie: session=<value>
Accept: application/json
```

Response (guess):

```json
{ "balance": 12.34, "currency": "CNY" }
```

Adapter decodes `balance` as `Double` and renders a single `Quota(unit: "¥")`.

## Status

Stub — endpoint, cookie name, and JSON shape not yet verified against the live
service. Task 17 smoke will replace with actual findings (and adjust
`SiliconFlowAdapter` `decoder` if the schema differs).