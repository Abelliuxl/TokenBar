# Recon — Provider 字段侦察工具（设计 Spec）

**作者**：liuxiaoliang
**日期**：2026-07-05
**状态**：✅ 已实现（v1: WKWebView Recon）→ 🚀 v2: 由 Chrome CDP inspect 替代

> **2026-07-05 更新**：原 Recon.app（WKWebView 方案）已被 `scripts/inspect.sh`
> （Chrome DevTools Protocol 方案）取代。本 spec 保留作为设计历史参考，
> 当前实现请见 `scripts/Inspector/` 和 `scripts/inspect.sh`。
> 
> 替代原因：Chrome 149 CDP WebSocket 要求 text frames（不支持 binary data），
> 且 WKWebView 无法处理复杂登录（2FA/SSO）。CDP 方案的真实浏览器环境
> 解决了这些问题。

---

## 1. 目的

解决 TokenBar 主项目的 5 个 Adapter 中，3 个 HTTP Adapter（火山引擎 / DeepSeek / 硅基流动）的 endpoint URL 和 JSON 字段名是**猜测的**这一阻塞。Recon.app 是独立的一次性侦察工具，让作者通过"看侦察结果"来判断哪个字段才是真余额 / 额度。

## 2. 形式 / 边界

- 独立 `.app`，不复用 TokenBar 主项目任何 `.swift` 文件
- 不动 TokenBar 主项目任何文件（除新增 `scripts/build_recon.sh`）
- 一次性工具，5 个 Provider 调研完后**可删**
- LSUIElement=YES（无 Dock 图标）

## 3. 命令行

```bash
./scripts/build_recon.sh
open Recon/build/Recon.app --args --provider volcano --url https://console.volcengine.com
```

- `--provider`：仅作文件名后缀（默认 `volcano`）
- `--url`：要加载的页面 URL（默认 `https://console.volcengine.com`）

## 4. 工作流程

1. 窗口弹出 → 加载 URL → WKWebView 自动注入 3 个 WKUserScript
2. 用户在窗口里**手动登录**（用自己账号）
3. 用户点工具栏 **"🔍 Scan"** 按钮（或 ⌘R）
4. Recon 收集证据：
   - `evaluateJavaScript(collectJS)` 拿 DOM hits、network requests（fetch+XHR）、localStorage、sessionStorage、`document.cookie`
   - native 调 `WKWebsiteDataStore.httpCookieStore.getAllCookies` 补 HttpOnly cookie
   - 合并成 `ReconReport` JSON
5. 写文件到 `Recon/build/recon-<provider>-<timestamp>.json`
6. 终端打印路径

## 5. 关键技术决策

### 5.1 WKUserScript 注入时机

- **atDocumentStart**：`networkHookJS` 替换 `window.fetch` 和 `XMLHttpRequest.prototype`，必须在页面脚本调用 fetch 之前覆盖
- **atDocumentEnd**：`domScanJS` walk DOM 文本节点，必须在 DOM 树构建后

### 5.2 网络 hook JS

不阻断请求，仅观察。所有 response body **不截断**——给用户看到原始 JSON / HTML 完整内容（避免截断后看不出关键字段）。

### 5.3 Cookie 双路采集

`document.cookie` 拿不到 HttpOnly，所以：
- JS 路径拿 document.cookie
- Native 路径拿 httpCookieStore.getAllCookies
- 合并去重，HttpOnly 字段从 native 补充

## 6. JSON schema

```json
{
  "capturedAt": "2026-07-05T12:34:56Z",
  "provider": "volcano",
  "url": "https://console.volcengine.com/...",
  "title": "...",
  "cookies": [{"name":"...","value":"...","domain":"...","httpOnly":true,"path":"...","secure":true}],
  "localStorage": {"key":"value", ...},
  "sessionStorage": {...},
  "domHits": [{"text":"账户余额 ¥108.50","tag":"div","id":"balance","cls":"...","path":"html>body>div#app>..."}],
  "requests": [{"method":"GET","url":"https://...","status":200,"responseType":"application/json","response":"<raw body>","startedAt":...,"type":"fetch"}]
}
```

## 7. 验收

- [ ] `./scripts/build_recon.sh` 产出 `Recon/build/Recon.app`
- [ ] `open` 弹窗
- [ ] 登录后 Scan → JSON 出现且 > 1KB
- [ ] JSON 同时含 `cookies`、`domHits`、`requests` 三个非空数组

## 8. 不做的事（明确）

- ❌ 不解析"哪个是余额"——这是作者人眼判断
- ❌ 不写任何 Adapter 代码
- ❌ 不上传任何数据
- ❌ 不持久化登录态
- ❌ 不复用主项目任何 Swift 源文件

## 9. 调研顺序

火山引擎 → DeepSeek → 硅基流动 → MiniMax → opencode go

每个 Provider：用户贴一份 JSON 给 AI，AI 只读不写，等用户判断完字段再动 Adapter。

---

✅ **End of Recon Spec**
