# TokenBar

macOS menu bar app that shows your AI / cloud service quotas at a glance.

> 自己用的小工具：不签名、不上架、不收集遥测。登录态只保存在 WKWebView 的持久 cookie store。

## Quick start

```bash
./scripts/build.sh       # 生成 build/TokenBar.app
./scripts/smoke.sh       # 启动 .app，4 秒后看是否还活着
open build/TokenBar.app
```

首次使用：
1. 点击菜单栏的 TokenBar 图标 → 下拉面板展开
2. 每个 Provider 在未登录状态显示"登录"按钮
3. 点登录 → 弹出 WKWebView 登录窗口
4. 关闭登录窗口 → App 自动 polling（默认每 300 秒）
5. 菜单栏图标颜色反映最紧急的 quota 状态（绿/黄/红）

## Providers (v1)

| ID | 服务名 | 抓取模式 | 字段 |
|---|---|---|---|
| `opencode-go` | opencode go | WKWebView + JS | 5h / 周 / 月 |
| `minimax` | MiniMax | WKWebView + JS | 订阅 |
| `siliconflow` | 硅基流动 | HTTP (cookie auth) | 余额 ¥ |
| `deepseek` | DeepSeek | HTTP (cookie auth) | 余额 ¥ |
| `volcano` | 火山引擎 | HTTP (cookie auth) | 余额 ¥ |
| `openrouter` | OpenRouter | WKWebView + JS | Credits $ |

## Adding a new Provider

### 1. Endpoint Discovery

先调研 Provider 的真实 API endpoint 和 JSON/DOM 结构：

```bash
# 1) 启动带调试端口的 Chrome
/Applications/Google\ Chrome.app/Contents/MacOS/Google\ Chrome \
  --remote-debugging-port=9222

# 2) 在该 Chrome 中登录 Provider，进入账单/用量页

# 3) 运行 inspect 工具监听网络请求
./scripts/inspect.sh --provider <id> --url <provider-url> --verbose

# 4) 在浏览器刷新页面，工具自动匹配含余额/额度的 JSON
# 5) Ctrl+C 查看汇总报告
# 6) 将确认的 endpoint 和字段写入 docs/research/<id>-research.md
```

工具通过 Chrome DevTools Protocol 直连浏览器，捕获所有网络请求并自动匹配 `balance`、`quota`、`余额`、`used`、`total` 等字段。详见 `scripts/inspect.sh --help`。

### 2. 实现 Adapter

1. 在 `Sources/TokenBar/Adapters/` 新建 `<Name>Adapter.swift`，实现 `ProviderAdapter` 协议
   - **HTTP 模式**（有 REST API）：参考 `SiliconFlowAdapter.swift`，composition 包装 `HTTPAdapter`
   - **WebView 模式**（SSR / 无 API）：参考 `OpenCodeGoAdapter.swift`，subclass `WebViewAdapter`
2. 在 `Sources/TokenBar/ProvidersRegistry.swift` 的 `default.adapters` 数组里加一行
3. （可选）在 `docs/research/<id>-research.md` 写调研笔记
4. 重跑 `./scripts/build.sh`

合约类型在 `Sources/TokenBar/Adapters/Core/ProviderAdapter.swift`。"Provider Registry 完全硬编码"是 v1 决策，不提供 JSON/UI 配置。

## Privacy

- 登录态由 **WKWebView persistent website data store** 保存；App 不读写 macOS Keychain
- 没有任何 telemetry、上报、远端统计
- 出站网络流量**仅**到各 Provider 自己的域名（WKWebView 登录页 / API endpoint）
- `secret_scan.sh` 在 build 前扫描源码，确保没有真实 secret 泄漏到 git

## Tech Stack

100% native Swift / SwiftUI. 零第三方依赖，零 Xcode 工程，零 SPM 依赖。`scripts/build.sh` 用 `swiftc` 直接编出 `.app`。

> 参考：`~/Workplace/MemoryPressureBar` 是同样的"纯 swiftc + shell"模式。

## Design / Plan docs

- Spec: `docs/superpowers/specs/2026-07-05-tokenbar-design.md`
- Plan: `docs/superpowers/plans/2026-07-05-tokenbar-impl.md`

## Endpoint Discovery

Adapter endpoints and JSON field names are initially **unknown**. Use the
CDP-based inspector to discover them:

```bash
# 1. Start Chrome with remote debugging
/Applications/Google\ Chrome.app/Contents/MacOS/Google\ Chrome \
  --remote-debugging-port=9222

# 2. In that Chrome window, open the provider's console and log in.

# 3. Run the inspector; it connects to Chrome and monitors traffic:
./scripts/inspect.sh --provider deepseek --url https://platform.deepseek.com

# 4. Navigate to the billing page in Chrome. The inspector prints matched
#    responses in real time. Press Ctrl+C to see the final report.
```

The inspector connects to Chrome's DevTools Protocol via WebSocket, monitors
all network traffic, and auto-detects JSON responses containing
balance/quota-related fields (`balance`, `quota`, `余额`, `used`, `total`, …).
No WKWebView, no JS injection — just the real browser.

## Layout

```
TokenBar/
├── Sources/TokenBar/
│   ├── *.swift          # Core (AppState / Poller / AppDelegate …)
│   ├── Adapters/
│   │   ├── Core/        # ProviderAdapter.swift, WebViewAdapter.swift, HTTPAdapter.swift
│   │   └── *.swift      # One concrete adapter per provider
│   └── Views/           # SwiftUI views (PopoverContent / ProviderSection / QuotaRow / LoginWindow)
├── scripts/
│   ├── build.sh         # Build TokenBar.app
│   ├── inspect.sh       # Chrome CDP endpoint discovery tool
│   │   └── Inspector/   # Swift source for the inspector
│   ├── smoke.sh         # Smoke test
│   ├── generate_icon.py # App icon generation
│   └── secret_scan.sh   # Pre-build secret scanner
├── Resources/
├── tests/
├── docs/
│   ├── research/        # Per-provider endpoint research notes (*.md)
│   └── superpowers/     # Design specs and implementation plans
├── Info.plist
└── README.md
```

## Acceptance criteria

- [x] `./scripts/build.sh` produces a runnable .app (and runs `secret_scan.sh` first)
- [x] `./scripts/smoke.sh` passes (4-second alive check)
- [x] All 5 sections appear in popover
- [ ] Logging into 1 provider yields a `Snapshot.status == .ok` (deferred — needs real account + manual selector tweak in research/)
- [x] Missing/invalid WebKit cookies trigger `.needsRelogin` UI
- [x] `scripts/secret_scan.sh` blocks build on planted secrets

## License

Personal; not for redistribution.
