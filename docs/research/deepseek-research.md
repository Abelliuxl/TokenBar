# DeepSeek Research ✅ 已验证

Provider: DeepSeek
Login URL: https://platform.deepseek.com
Usage URL: https://platform.deepseek.com/usage

## 验证方式

1. Chrome DevTools Protocol (inspect 工具) 连接 Chrome
2. 登录后在用量页刷新
3. 捕获网络请求

## 余额 API

**Endpoint（已验证）**
```
GET https://platform.deepseek.com/auth-api/v0/users/current
```

**Response 结构**
```json
{
  "code": 0,
  "data": {
    "biz_data": {
      "normal_wallets": [{
        "balance":           "21.8350080800000000",   // 余额（CNY，String）
        "currency":          "CNY",
        "token_estimation":  "7278336"                // 可用 Token 估算
      }],
      "bonus_wallets": [{
        "balance":           "0",
        "currency":          "CNY",
        "token_estimation":  "0"
      }],
      "monthly_costs": [{
        "amount":   "2.0605757600000000",              // 本月消费
        "currency": "CNY"
      }],
      "monthly_usage":                  "24095722",   // 本月 Token 用量
      "monthly_token_usage":            "24095722",
      "total_available_token_estimation": "7278336",  // 总计可用 Tokens
      "current_token":                  10000000
    }
  }
}
```

**字段映射**
- `data.biz_data.normal_wallets[0].balance` → 余额（String → Double，单位 CNY）
- `data.biz_data.normal_wallets[0].token_estimation` → 可用 Token 数
- `data.biz_data.monthly_costs[0].amount` → 本月消费
- `data.biz_data.total_available_token_estimation` → 总计可用 Token

## 其他发现的端点

### 用量明细
```
GET /api/v0/usage/amount?month=7&year=2026
```
按天返回 PROMPT_TOKEN / RESPONSE_TOKEN 等用量。

### 费用明细
```
GET /api/v0/usage/cost?month=7&year=2026
```

## Cookie

- Cookie-based auth（session cookie）
- 请求中携带 session cookie 即可认证

## Adapter 更新

DeepSeekAdapter 需要修改：
- Endpoint: `platform.deepseek.com/auth-api/v0/users/current`
- 字段: `response["data"]["biz_data"]["normal_wallets"][0]["balance"]` as String → Double

## 状态

✅ 已验证 — 2026-07-05
