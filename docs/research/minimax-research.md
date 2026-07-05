# MiniMax Research ✅ 已验证

Provider: MiniMax
Login URL: https://platform.minimaxi.com
Usage URL: https://platform.minimaxi.com/console/usage

## 验证方式

1. Chrome DevTools Protocol (inspect 工具) 连接 Chrome
2. 登录后在用量页刷新
3. 捕获网络请求 + DOM 分析

## 架构决策：WebViewAdapter

MiniMax 的额度数据是 **服务端渲染（Next.js SSR）** 的，没有客户端 API 返回结构化的配额数据。因此：
- ❌ HTTPAdapter 不可行（`/v1/api/openplatform/coding_plan/remains` 返回 `"no active token plan subscription"`）
- ✅ WebViewAdapter + DOM 抓取是正确的方案

## DOM 结构

额度卡片位于"套餐用量"区块，每个配额是一个 `div` 带 `aria-label`：

### 5h 限额

```html
<div class="grid grid-cols-[120px_minmax(0,1fr)_auto] items-center gap-3"
     aria-label="5h 限额 15%">
  <div class="min-w-0">
    <div class="text-xs text-ui-muted-foreground flex items-center gap-1">
      <span class="truncate">5h 限额</span>
    </div>
    <div class="text-[11px] text-ui-muted-foreground/80">
      48 分钟后重置
    </div>
  </div>
  <!-- progress bar -->
</div>
```

### 周限额

```html
<div class="grid grid-cols-[120px_minmax(0,1fr)_auto] items-center gap-3"
     aria-label="周限额 35%">
  <!-- 同上结构 -->
  <div class="text-[11px] text-ui-muted-foreground/80">
    9 小时 48 分钟后重置
  </div>
</div>
```

## 抓取策略

```
选择器: [aria-label*="5h"]  → 匹配 "5h 限额 15%"
选择器: [aria-label*="周限额"] → 匹配 "周限额 35%"
提取: aria-label 末尾的数字（正则匹配 [\d.]+(?=%$)）
```

## 重置时间

重置时间在 DOM 中为自然语言文本（如 "48 分钟后重置"、"9 小时 48 分钟后重置"），
不易程序化解析。Quota 模型的 `resetsAt` 字段暂不填充。

## Cookie / Auth

- Cookie-based auth（session cookie）
- `_token` 和 `_sid` 是主要的认证 cookie
- 通过 WKWebView 登录后自动保存到 Keychain

## 其他端点（参考）

以下 API 端点存在但该用户无数据（无 token plan 订阅）：

| 端点 | 响应 |
|------|------|
| `/v1/api/openplatform/coding_plan/remains` | `"no active token plan subscription"` |
| `/backend/account/token_plan_credit` | `total_credits: 0` |
| `/backend/account/token_plan/usage_summary` | 有每日用量汇总 |
| `/v1/api/openplatform/charge/token_plan/usage` | `total: 0` |

## Adapter 更新

MinimaxAdapter (WebViewAdapter)：
- URL: `https://platform.minimaxi.com/console/usage`（之前是 `api.minimax.chat`）
- 选择器: `[aria-label*="5h"]` 和 `[aria-label*="周限额"]`
- 解析: 从 aria-label 中提取百分比

## 状态

✅ 已验证 — 2026-07-05
