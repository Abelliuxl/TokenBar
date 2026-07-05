# opencode go Research ✅ 已验证

Provider: opencode go
Login URL: https://opencode.ai/workspace/wrk_01KVB7CEDBFN8VF6FYA2DJ1GR3/go
Usage URL: https://opencode.ai/workspace/{workspace_id}/go

## 验证方式

1. Chrome DevTools Protocol (inspect 工具) 连接 Chrome
2. 登录后在用量页刷新
3. DOM 分析 + 网络请求捕获

## 架构决策：WebViewAdapter

opencode go 的用量数据是完全服务端渲染（SSR）的，没有 HTTP API：
- ❌ `/api/usage` → 404
- ❌ `/api/ai/opencode-go/usage` → 404
- ❌ `/api/workspace/usage` → 404
- 所有网络请求只有字体文件（woff2）
- ✅ WebViewAdapter + DOM 抓取是正确的方案

## DOM 结构

用量卡片使用 `data-slot` 属性，结构非常规整：

```html
<div data-slot="usage-item">
  <div data-slot="usage-header">
    <span data-slot="usage-label">滚动用量</span>
    <span data-slot="usage-value">2%</span>
  </div>
  <div data-slot="progress">
    <div data-slot="progress-bar" style="width:2%"></div>
  </div>
  <span data-slot="reset-time">重置于 36 分钟</span>
</div>
```

### 三个额度

| 类型 | data-slot="usage-label" | 当前已用 | 重置时间 |
|------|------------------------|---------|---------|
| 滚动用量 | `滚动用量` | 2% | 36 分钟 |
| 每周用量 | `每周用量` | 95% | 17 小时 41 分钟 |
| 每月用量 | `每月用量` | 68% | 12 天 10 小时 |

## 抓取策略

```javascript
// 选择器
const items = document.querySelectorAll('[data-slot="usage-item"]');
// 每个 item 内：
const label = item.querySelector('[data-slot="usage-label"]').textContent;
const pct = parseInt(item.querySelector('[data-slot="usage-value"]').textContent);
const reset = item.querySelector('[data-slot="reset-time"]').textContent;
```

## URL 说明

工作区 URL 包含用户唯一的 workspace ID：
`https://opencode.ai/workspace/wrk_xxxxx/go`

`loginURL` 直接设为当前账号的 Go 工作区页面：
`https://opencode.ai/workspace/wrk_01KVB7CEDBFN8VF6FYA2DJ1GR3/go`。

旧的 `https://opencode.ai/dashboard` 已返回 404，不能作为入口。

## 数值语义

页面上显示的是**已用百分比**：
- 2% 表示已用 2%
- Adapter 直接使用页面百分比作为 `used`

## 状态

✅ 已验证 — 2026-07-05
