# OpenCode Go 用量抓取研究（2026-09-21）

## 官网变化

- 旧版入口 `/workspace/{workspace_id}/go` 在旧 Console 中渲染 `data-slot="usage-item"`。原适配器还把一个用户的工作区 ID 写死在 URL 中。
- 新版 Console 入口是 `https://opencode.ai/console/`；组织页面路由为 `/console/{org_id}/go`。新版 Go 页面已改用前端渲染，三档额度的进度条带 `role="progressbar"`、`aria-label="Rolling usage used"` 等标签，以及 `aria-valuenow` 百分比。重置时间在卡片内的带 `title` 元素上。
- 新版页面按 `fiveHour`、`week`、`month` 显示滚动、每周、每月用量。官网仍列出这三档额度。

## 新增官方 API

OpenCode [已合并的 PR #16513](https://github.com/anomalyco/opencode/pull/16513) 增加了 `GET https://opencode.ai/zen/go/v1/usage`。无 API key 时，该地址返回 HTTP 401 `Missing API key.`。服务端代码使用 `Authorization: Bearer <Go API key>`，返回：

```json
{
  "usage": {
    "rolling": {"status":"ok", "percent":12.5, "resetsAt":"2026-09-21T18:30:00.000Z"},
    "weekly": {"status":"ok", "percent":42, "resetsAt":"2026-09-28T00:00:00.000Z"},
    "monthly": {"status":"ok", "percent":73, "resetsAt":"2026-10-21T00:00:00.000Z"}
  }
}
```

这份 JSON 是结构示例，不是账号实测数据。API 模式需要用户在 TokenBar 中单独填写 Go API key；WebKit 登录 cookie 不能代替 Bearer key。

## TokenBar 实现

- 默认仍使用网页登录，打开 Console 首页，跟随当前组织的 Go 链接，抓取三条进度条；旧页面选择器保留作为迁移兼容。
- 右键菜单的“爬取模式 → 官方 API”可选择结构化接口，API key 保存在现有凭证存储中。
- 网页抓取只接受可识别的窗口标签和 0–100 范围内的百分比，不再按卡片顺序猜测窗口，也不再从全文的首个百分比推断额度。

来源：[新版 Go 页面](https://opencode.ai/console/)、[官网 Go 文档](https://opencode.ai/v2/docs/console/go)、[新版前端的 Go 页面代码包](https://opencode.ai/console/assets/page-CijxkKcO.js)、[官方接口服务端代码](https://github.com/anomalyco/opencode/blob/dev/packages/console/app/src/routes/zen/go/v1/usage.ts)。

旧版 DOM 与路由的调查见该文件的 Git 历史。当前无法在未提供账号登录态的环境中端到端验证个人额度，因此上线后应在已登录的 TokenBar 中确认三条额度均出现。
