# OpenRouter Research

Provider: OpenRouter
Credits URL: https://openrouter.ai/settings/credits

## 数据源

官方 credits API:

```
GET https://openrouter.ai/api/v1/credits
```

官方文档说明响应结构：

```json
{
  "data": {
    "total_credits": 100.5,
    "total_usage": 25.75
  }
}
```

余额计算：

```
balance = data.total_credits - data.total_usage
```

## TokenBar 双途径实现

`OpenRouterAdapter` 提供两种途径：

- `网页登录`：打开 `https://openrouter.ai/settings/credits`，复用 WebKit 登录态：
  1. 页面内同步尝试 `GET /api/v1/credits`
  2. 如果同源 API 不可用，回退到页面文本中的美元余额
  3. 只显示 credits 余额数字，不显示进度条
- `官方 API`：读取用户配置的 Bearer API key，请求 `https://openrouter.ai/api/v1/credits`。

官方文档当前标注 Credits API 需要 Management API Key；实测普通 `sk-or-v1-...` API key 也返回 HTTP 200 和完整的 `total_credits` / `total_usage` 字段，因此 TokenBar 使用同一个 API key 输入位置兼容两种 key。若 OpenRouter 后续严格执行文档限制，配置 Management API Key 即可继续使用。

参考：[Get remaining credits](https://openrouter.ai/docs/api/api-reference/credits/get-remaining-credits)、[Management API Keys](https://openrouter.ai/docs/guides/overview/auth/management-api-keys)。

## 状态

网页途径为初版实现；官方 API 途径已接入，余额计算为 `total_credits - total_usage`。
