# SiliconFlow Research ✅ 已验证

Provider: 硅基流动 (SiliconFlow)
Login URL: https://cloud.siliconflow.cn
Billing URL: https://cloud.siliconflow.cn/me/expensebill

## 验证方式

1. Chrome DevTools Protocol (inspect 工具) 连接 Chrome
2. 登录后在账单页刷新
3. 捕获网络请求

## 余额 API

**Endpoint（已验证）**
```
GET https://cloud.siliconflow.cn/walletd-server/api/v1/subject/profile/peek
```

**Response 结构**
```json
{
  "code": 20000,
  "data": {
    "financialInfo": {
      "balance":    "63060715770000",   // 当前余额（String）
      "available":  "63060715770000",
      "used":       "86939284230000",   // 已消费
      "recharged":  "150000000000000",  // 累计充值
      "lineOfCredit": "0",
      "remainingCreditLine": "0"
    }
  }
}
```

**字段映射**
- `data.financialInfo.balance` → 余额（String，需转为 Double）
- `data.financialInfo.used` → 已用额度

**单位说明**
API 返回的数值为 `×10^12` 的整数（String 类型），页面显示时除以 10^12。
例如 API 返回 `"63060715770000"`，页面显示 63.0607。

## 其他发现的端点

### 赠金余额
```
GET /walletd-server/api/v1/subject/wallets?pageSize=1&stage=3&visible=1&serviceable=1
```
- `data.wallets[0].balance` — 赠金余额（Number，1306290198704）
- `data.wallets[0].used` — 赠金已用（Number）

### 权限查询
```
GET /iam-server/api/v1/my/authz/allowed_actions
```

## Cookie

- Cookie-based auth（session cookie）
- Cookie 由浏览器登录后设置，通过 Keychain 注入到 HTTPAdapter

## Adapter 更新

SiliconFlowAdapter 需要修改：
- Endpoint: `cloud.siliconflow.cn/walletd-server/api/v1/subject/profile/peek`
- 字段: `response["data"]["financialInfo"]["balance"]` as String → Double
- 可以同时暴露 `used` 字段

## 状态

✅ 已验证 — 2026-07-05
