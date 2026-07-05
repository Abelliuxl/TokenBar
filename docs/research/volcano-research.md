# Volcano Engine Research ✅ 已验证

Provider: 火山引擎 (Volcano Engine)
Login URL: https://console.volcengine.com
Billing URL: https://console.volcengine.com/finance/account-overview/

## 验证方式

1. Chrome DevTools Protocol (inspect 工具) 连接 Chrome
2. 登录后在费用总览页刷新
3. 捕获网络请求

## 余额 API

**Endpoint（已验证）**
```
GET https://console.volcengine.com/api/top/bill_volcano_engine/cn-north-1/2020-01-01/GetBalanceFromTradeBalance
```

**Response 结构**
```json
{
  "ResponseMetadata": {
    "Action": "GetBalanceFromTradeBalance",
    "Region": "cn-north-1",
    "Service": "bill_volcano_engine",
    "Version": "2020-01-01"
  },
  "Result": {
    "Acct": {
      "AvailableBalance":  "20.29",     // 可用余额（String）
      "CashBalance":       "20.29",     // 现金余额
      "CarryOverBalance":  "20.29",     // 结转余额
      "ArrearsBalance":    "0",         // 欠费金额
      "Currency":          "CNY",
      "PricingCurrency":   "CNY",
      "CreditLimit":       "0",         // 信用额度
      "CreditVersion":     0,
      "AlertThreshold":    "0",
      "AlertFlag":         0,
      "AccountID":         2111147899,
      "CombineName":       "刘晓亮（4714_Douyin#fDRqpl）"
    }
  }
}
```

**字段映射**
- `Result.Acct.AvailableBalance` → 可用余额（String → Double，单位 CNY）
- `Result.Acct.CashBalance` → 现金余额
- `Result.Acct.CarryOverBalance` → 结转余额
- `Result.Acct.Currency` → 币种

## 其他发现的端点

### 积分账户
```
GET .../QueryPointAccountRemainAmount
```
- 积分余额（该账户无积分，返回 0）

### 月账单
```
GET .../ListMonthlyBillOpen?BillPeriodBeginStr=...&BillPeriodEndStr=...
```

### 续费设置
```
GET .../ListRenewSettings?RenewType=...
```

### 优惠券
```
GET .../CountCoupon
```

### 发票账户
```
GET .../GetInvoiceAccount
```

## Cookie / Auth

- Cookie-based auth（session cookie）
- 火山引擎使用 `top/bill_volcano_engine` API 网关模式
- 所有 `/api/top/bill_volcano_engine/...` 端点共享同一个 session

## Adapter 更新

VolcanoEngineAdapter 需要修改：
- Endpoint: `console.volcengine.com/api/top/bill_volcano_engine/cn-north-1/2020-01-01/GetBalanceFromTradeBalance`
- 字段: `response["Result"]["Acct"]["AvailableBalance"]` as String → Double
- 不需要特殊 headers（cookie 认证即可）

## 状态

✅ 已验证 — 2026-07-05
