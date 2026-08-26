# DeepSeek Research ✅ 已验证

Provider: DeepSeek
Login URL: https://platform.deepseek.com
Usage URL: https://platform.deepseek.com/usage

## 验证方式

1. Chrome DevTools Protocol (inspect 工具) 连接 Chrome
2. 登录后在用量页刷新
3. 捕获网络请求

## 官方余额 API（API 请求途径）

DeepSeek 官方 API 文档现在提供了独立的余额接口：

**Endpoint（官方文档）**
```
GET https://api.deepseek.com/user/balance
Authorization: Bearer <DEEPSEEK_API_KEY>
```

响应结构：
```json
{
  "is_available": true,
  "balance_infos": [{
    "currency": "CNY",
    "total_balance": "110.00",
    "granted_balance": "10.00",
    "topped_up_balance": "100.00"
  }]
}
```

TokenBar 将 `total_balance` 按币种显示为余额；支持官方文档列出的 CNY 和 USD。此接口返回钱包余额和 API 可用性，不返回按日用量明细。

参考：[DeepSeek 查询余额 API](https://api-docs.deepseek.com/zh-cn/api/get-user-balance/)、[DeepSeek API 认证](https://api-docs.deepseek.com/api/deepseek-api/)。

## 网页登录途径（兼容保留）

网页途径继续使用已验证的登录态接口：

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

## TokenBar 双途径实现

- `网页登录`：通过 WebView persistent cookie 请求 `platform.deepseek.com` 的网页接口。
- `官方 API`：通过用户配置的 API Key 请求 `api.deepseek.com/user/balance`。
- API Key 只用于 API 途径，和网页登录态分开保存。

## 状态

✅ 网页接口已验证 — 2026-07-05；官方 API 依据当前官方文档接入
