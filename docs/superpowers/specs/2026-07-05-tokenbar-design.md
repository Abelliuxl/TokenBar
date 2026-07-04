# TokenBar — 设计 Spec

**作者**：liuxiaoliang
**日期**：2026-07-05
**状态**：草案 v1（待用户审阅）

---

## 1. 目标

打造一款 macOS 菜单栏（Status Bar）常驻 App **TokenBar**，点击/悬停时弹出一个下拉面板，集中展示用户在多个 AI / 云服务上订阅的**剩余额度（quota）和账户余额**，让用户**一眼看出自己的 token 还剩多少、钱还剩多少**。

## 2. 非目标（YAGNI）

- 不做通知系统（不主动发 OS 通知）
- 不做历史记录/趋势图（v1 只显示当前快照）
- 不做多用户、不做团队共享
- 不上架、不签名分发（仅本地自用）
- 不支持 iPadOS / iOS / Windows / Linux
- 不做更新检测 / 自动升级
- 不内置任何已 hard-code 的账号（用户的登录态必须由用户在 App 内登录取得，源码中不应出现任何真实账号、cookie、token）

## 3. 目标用户与平台

- **唯一用户**：作者本人（macOS 26，"Tahoe" 或更新）
- **最低系统版本**：macOS 14.0（提供 `MenuBarExtra`/SwiftUI 完整 API；面向未来兼容 macOS 26）
- **架构**：Universal（arm64 + x86_64），但开发机为 arm64

## 4. 名词

| 术语 | 含义 |
|---|---|
| **Provider** | 一个被监控的服务源（如 opencode go、MiniMax、硅基流动等） |
| **Snapshot** | 一次抓取后某个 Provider 返回的当前额度快照 |
| **Session** | 用户的登录态。存到 Keychain，App 重启复用 |
| **Adapter** | 实现 `ProviderAdapter` 协议的具体 Provider 抓取逻辑 |
| **Poller** | 后台定时任务，按 Provider 列表依次/并发触发抓取 |

## 5. 监控源（v1 必须实现）

> **Provider 列表策略（v1 决策）**：Provider **完全硬编码**于源码（`Sources/TokenBar/Adapters/` 下每个 Adapter 一个 Swift 文件）。新增一个 Provider = 新增一个 Adapter Swift 文件 + 在 `ProvidersRegistry` 里登记一行 + 重新编译。**不**提供 JSON/YAML/UI 配置层添加。
> 理由：动态配置虽灵活，但会迫使所有 Provider 退化成"通用模板"，丢掉 WKWebView 之类灵活抓取能力，且会让调试变难。个人工具，迭代频率低，硬编码更简单直接。

| ID | 服务 | 字段 | 抓取方式 |
|---|---|---|---|
| `opencode-go` | opencode go | 5h 额度、周额度、月额度 | WKWebView（默认 JS 抽取；当页面有明文 XHR 调用时优先拦截 fetch） |
| `minimax` | MiniMax（MiniMax） | 订阅剩余额度 | WKWebView（同上策略） |
| `siliconflow` | 硅基流动 | 账户余额（元） | 纯 HTTP（XHR/JSON） |
| `deepseek` | DeepSeek | 账户余额（元） | 纯 HTTP |
| `volcano` | 火山引擎 | 账户余额（元） | 纯 HTTP |

> 留 1 个 `generic-http` 占位（v1 不需要实现，但协议层预留）。

> **调研方式（v1 决策）**：识别"哪段 DOM / 哪个 endpoint 是额度字段"，作者**使用外部独立工具**（Chrome DevTools、Charles、Playwright、cURL 等）手动调研，把结论写到 `docs/research/<provider>-research.md`，再据此写 Adapter。**TokenBar App 本身不带 Probe/Dev 窗口**——避免 App 体积膨胀、避免 UI 复杂度上升。
> 优势：把"探查"和"展示"两件事彻底解耦。

## 6. 架构总览

```
┌──────────────────────────────────────────────────────────┐
│                       TokenBar.app                       │
├──────────────────────────────────────────────────────────┤
│ StatusItem (NSStatusItem + MenuBarExtra)                 │
│   ├─ 图标（按整体健康度变色：全绿/有黄/有红）             │
│   └─ 标题可选：显示"最紧急项"的百分比                     │
├──────────────────────────────────────────────────────────┤
│ Popover（SwiftUI 视图，约 320pt 宽，自适应高）           │
│   ├─ Header（最后抓取时间，下拉手动刷新按钮）             │
│   ├─ Sections（一个 Provider 一段）                      │
│   │   ├─ SectionHeader（logo + 服务名 + 状态点）          │
│   │   ├─ QuotaRow（进度条 + "已用 X / 总额 Y" + 重置时间）│
│   │   └─ 多个 QuotaRow                                    │
│   ├─ Footer ([立即刷新] [打开设置] [退出])               │
├──────────────────────────────────────────────────────────┤
│ Core 层                                                  │
│   ├─ AppState（@MainActor，ObservableObject）           │
│   ├─ ProvidersRegistry（启用的 Provider 列表）            │
│   ├─ Poller（每 N 秒一轮，Async并发抓取）                │
│   ├─ Adapter 协议（异步 fetch → Snapshot）              │
│   ├─ WebViewSessionManager（WKWebView + JS Bridge）      │
│   ├─ KeychainStore（Security framework）                 │
│   ├─ SettingsStore（@AppStorage）                        │
│   └─ IconRenderer（按状态合成状态栏图标）                 │
└──────────────────────────────────────────────────────────┘
```

### 6.1 ProviderAdapter 协议

```swift
protocol ProviderAdapter: Identifiable, Sendable {
    var id: String { get }                  // "opencode-go"
    var displayName: String { get }         // "opencode go"
    var iconSystemName: String { get }      // SF Symbol 名
    var fetchMode: FetchMode { get }        // .webView | .http
}

enum FetchMode {
    case webView(WebViewConfig)   // 入口 URL，JS 注入点，等待 selector
    case http(HttpConfig)         // method/url/headers/body 模板
}

struct Snapshot: Sendable {
    let providerId: String
    let capturedAt: Date
    let quotas: [Quota]
    let status: ProviderStatus  // .ok / .needsRelogin / .error(message)
}

struct Quota: Identifiable, Sendable {
    let id: String
    let label: String             // "5h"、"周"、"月"、"余额"
    let used: Double
    let total: Double
    let unit: String              // "%"、"tokens"、"¥"
    let resetsAt: Date?
}
```

关键点：所有 Adapter 用 `async/await` 返回 `Snapshot`；不抛异常，错误转 `ProviderStatus`。

## 7. 关键流程

### 7.1 首次配置 Provider

1. 用户点击菜单栏图标 → 弹出 Popover
2. 若该 Provider 尚未登录，Section 显示"未登录 → 点此登录"
3. 点击 → 模态弹出独立窗口（NSWindow），内嵌 WKWebView 打开登录 URL
4. 监听 navigation finish 后从 WKWebView 取 `httpCookieStore.allCookies()`
5. 加密后写入 Keychain（key = `tb.session.<providerId>`）
6. 关闭登录窗口，回到 Popover，标记该 Provider 为已登录，下次轮询自动抓数据

### 7.2 定时抓取

```
Poller 单例
  ├─ tick 间隔默认 300s（用户可调 60-3600s）
  ├─ 每 tick：
  │   for provider in ProvidersRegistry.enabled:
  │     Task: adapter.fetch() → Snapshot → 写 AppState.snapshots[id]
  │   等所有 Task 收敛（TaskGroup）
  │   更新状态栏图标颜色 / 标题
```

### 7.3 Session 过期处理

- Snapshot.status == .needsRelogin 时：
  - 状态栏图标标黄/红
  - Popover 该 Provider 段落顶部出现"⚠️ Session 过期，点此重新登录"
  - 点击即启动 §7.1 流程

## 8. 数据存储

| 数据 | 位置 | 说明 |
|---|---|---|
| Session Cookie | Keychain（Service=`tokenbar-session`, Account=`<providerId>`） | 仅本次写入使用 `kSecAttrAccessibleAfterFirstUnlock` |
| Provider 启用列表 / 抓取间隔 | `UserDefaults`（`@AppStorage`） | 不敏感 |
| 最新 Snapshot 缓存 | 内存（`AppState`），每次 App 启动重新拉一次 | 不持久化快照 |

> v1 不设计 "Snapshot 数据库/历史趋势"。要历史，重新进 brainstorming。

## 9. UI 规范（SwiftUI）

- **Popover 宽度**：固定 320pt
- **配色**：跟随系统 Dark/Light Mode，`ProgressView` 使用 tint color = 系统 `accentColor`
- **状态颜色**：
  - `.ok` → 绿
  - `.warn`（剩余 ≤ 20%）→ 黄
  - `.danger`（剩余 ≤ 5% 或过期）→ 红
  - `.needsRelogin` → 灰 + 提示
- **状态栏图标**：3 套预渲染图标（绿/黄/红），运行时根据最差状态切换；标题可显示"最紧急的 %"

## 10. 安全 / 隐私

- App 不应申请"完全磁盘访问"、"辅助功能"、"屏幕录制"等危险权限
- 不开网络抓包代理，不读其他 App 的 keystroke
- cookie 仅用于受信任域名（Adapter 的 `webViewURL` 白名单里）
- 不向任何远端上传用户数据（**整个 App 没有任何 telemetry**）
- 源码不包含任何真实账号 / cookie / token（CI 用 Secret-Scanning 工具，针对 cookie 路径白名单豁免；不靠裸 `grep`）

## 11. 构建与分发

完全沿用同仓库 `MemoryPressureBar` 风格：

```
TokenBar/
├── Sources/
│   └── TokenBar/
│       ├── main.swift                      # 入口
│       ├── AppDelegate.swift
│       ├── StatusBarController.swift
│       ├── AppState.swift
│       ├── Poller.swift
│       ├── Adapters/
│       │   ├── ProviderAdapter.swift       # 协议 + 类型
│       │   ├── OpenCodeGoAdapter.swift
│       │   ├── MinimaxAdapter.swift
│       │   ├── SiliconFlowAdapter.swift
│       │   ├── DeepSeekAdapter.swift
│       │   └── VolcanoEngineAdapter.swift
│       ├── WebViewSessionManager.swift
│       ├── KeychainStore.swift
│       ├── IconRenderer.swift
│       └── Views/
│           ├── PopoverView.swift
│           ├── LoginWindowController.swift
│           └── ProgressRowView.swift
├── Resources/
│   ├── AppIcon.iconset/
│   └── AppIcon.icns
├── docs/
│   └── superpowers/specs/2026-07-05-tokenbar-design.md
├── scripts/
│   ├── build.sh
│   └── generate_icon.py
├── Info.plist
├── README.md
└── .gitignore
```

- **构建**：`scripts/build.sh`，纯 `swiftc` 命令行（无需 Xcode 工程，零 SPM 依赖，0 第三方库）
- **签名**：`codesign --force --sign -`（ad-hoc，仅本机自用）
- **安装**：build 出 `.app`，拖到 `~/Applications/` 或 `~/Library/Application Support/`
- **启动项**：LaunchAtLoginController（参考 MemoryPressureBar 实现，可关闭）

## 12. 测试

- v1 阶段**不做 UI 测试**（个人小工具，无明显 ROI）
- Core 层的 `KeychainStore`、`Adapter`（在协议层 + mock 实现）做 XCTest 单测
- 每个 Adapter 的实际抓取逻辑必须在作者的浏览器里手动验证后，把"已验证 selector / URL / cookie 名"写到 `docs/research/<id>-research.md`
- 写一个 `scripts/smoke.sh`：能 cold-start .app、轮询 1 次、查看日志无 panic

## 13. 风险与开放问题

| # | 风险 / 开放问题 | 处置 |
|---|---|---|
| R1 | 厂商改前端 DOM → Adapter 抓不到 | 每个 Adapter 留 5xx/timeout retry + 友好提示，研究文档保留历史 selector |
| R2 | cookie 过期 → 抓不到 → 误以为是额度归零 | ProviderStatus 强制区分 `.needsRelogin` 和 `.empty` |
| R3 | 厂商对 WKWebView 注入 JS 做 fingerprint 检测 | 用 `WKUserScript` `atEnd: true` 注入；尽量不读取 DOM，直接 fetch 已有 XHR |
| R4 | macOS 26 上的 SwiftUI 行为可能与 14 略有差异 | 启动后立即观察 Popover 行为；若崩，记录在 docs/issues/ |
| R5 | 余额展示币种（CNY / USD）| Adapter 自带 `currency` 字段，统一前缀展示（如 `¥108.5` / `$12.30`） |

## 14. 实施门槛（GTM 决策）

- 只有当用户在本 spec 上签字同意后，才进入 writing-plans 阶段
- implementation 阶段**仍要先小后大**：先 Adapter protocol + Keychain + Poller 骨架 + 1 个 demo Adapter（opencode go），跑通后再扩其余 4 个
- 每加一个 Provider，按 `docs/research/<id>-research.md` 模板先行调研

## 15. 与既有项目关系

- 借鉴 `MemoryPressureBar` 的"纯 swiftc + shell 构建"流程
- 与 `opencode-cny-cost`、`Mythic_Performance_Tracker` 等项目功能正交；不引用其代码、不共享包

---

✅ **End of Spec v1**

请用户审阅本文件。若同意，下一步是调用 `superpowers:writing-plans` skill，把 spec 拆成可执行的实施计划（仍然不写代码）。
