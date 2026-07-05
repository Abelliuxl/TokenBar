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

## TokenBar 实现

官方 API 要求 Bearer API key。TokenBar 不保存 OpenRouter API key，因此 `OpenRouterAdapter` 使用 `WKWebView` 打开 `https://openrouter.ai/settings/credits`，复用 WebKit 登录态：

1. 页面内同步尝试 `GET /api/v1/credits`
2. 如果同源 API 不可用，回退到页面文本中的美元余额
3. 只显示 credits 余额数字，不显示进度条

## 状态

初版实现，需登录真实账号后验证页面 DOM 文本兜底是否命中。
