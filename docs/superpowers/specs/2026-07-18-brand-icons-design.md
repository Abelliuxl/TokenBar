# 内置供应商品牌图标设计

日期：2026-07-18
状态：已获用户批准
分支：agent/brand-icons（base: agent/custom-field-picker 快照 bc25354）

## 背景

7 个内置供应商当前使用随意挑选的 SF Symbol 占位图标（bolt.fill、sparkles、cloud.fill、brain.head.profile、flame.fill、arrow.triangle.branch、terminal.fill），与真实品牌无关。目标：重绘真实品牌 logo，配色形态经设计适配（非无脑贴原 logo）。

## 渲染方式

代码绘制矢量图形（SwiftUI `Shape`，单位坐标归一化），不引入图片资源。

理由：项目为纯 `swiftc` 编译、无 asset catalog；图片需改 build.sh 且小尺寸发虚；矢量可任意缩放、可做深浅色自适应、零资源文件。

## 各品牌图形与配色（调研结论）

| 供应商 | id | 图形 | 配色 |
|---|---|---|---|
| DeepSeek | deepseek | 鲸鱼剪影（头朝左，尾鳍右上，眼点+微笑弧线） | `#5786FE` |
| 硅基流动 | siliconflow | 双圆角横条错位组成 S 阶梯（约 2:1） | `#6E29F5` |
| 火山引擎 | volcano | 5 座重叠三角峰（同一基线） | 蓝 `#006AFF` + 青 `#00DCFF` 双色 |
| MiniMax | minimax | 对称圆头竖条波形 | 渐变 `#E4177F → #E94E4A` |
| OpenRouter | openrouter | 2025 新标 "OR"：圆环 + 2 点位凸圆 + 45° 斜腿 + 平底线 | 浅色 `#7624F4` / 深色 `#C8FF00`（官方双色系） |
| opencode go | opencode-go | 像素方块 O：矩形环 + 孔内下部实心块 | 品牌即黑白 → 跟随文字色自适应 |
| Codex | codex | OpenAI 结形花（6 重旋转对称编织结，中心六边形负空间） | 品牌即黑白 → 跟随文字色自适应 |

路径数据来源：simple-icons CDN（deepseek、minimax、opencode）、Wikimedia（OpenAI 结）、按调研几何手绘（硅基流动、火山引擎、OpenRouter）。

## 代码结构

- `ProviderAdapter` 协议新增 `var brandIcon: BrandIcon? { get }`；协议扩展提供默认 `nil`。
  - 自定义供应商（CustomProviderAdapter 等）不受影响，继续使用 `iconSystemName`（默认 globe）。
- 新文件 `Sources/TokenBar/Views/ProviderBrandIcon.swift`：
  - `BrandIcon` 枚举（7 case，携带品牌色/渐变/自适应色规格）
  - 7 个 SwiftUI `Shape`（单位坐标，按 viewBox 归一化）
  - `ProviderBrandIconView`：有 `brandIcon` 画品牌图形，否则回退 `Image(systemName: provider.iconSystemName)`
- 调用点替换（2 处）：
  - `Sources/TokenBar/Views/ProviderSectionView.swift:136`（供应商列表头）
  - `Sources/TokenBar/Views/PopoverContentView.swift:236`（拖拽预览）
- 7 个内置 Adapter 各返回对应 `brandIcon` case。

## 错误处理 / 边界

- 无网络、无资源加载，绘制失败面为零；未知 provider（自定义）必走 SF Symbol 回退。
- 深色模式：OpenRouter 用官方深色色（`#C8FF00`）；opencode/Codex 用 `.primary` 自适应；其余品牌色在深浅底下均可读（中高明度）。

## 测试与验证

- `scripts/build.sh` 编译通过。
- 人工运行 App 肉眼确认 7 个图标形态与配色（浅色 + 深色模式）。
- 现有 `tests/` 不涉及 UI 渲染，无需新增测试。

## 流程

实现完成 → commit → push `agent/brand-icons` → PR（base: `agent/custom-field-picker`，diff 仅含本特性）→ merge。
