# Brand Icons Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 为 7 个内置供应商绘制真实品牌矢量图标，替换 SF Symbol 占位图标。

**Architecture:** 新增纯 SVG 路径解析层（`SVGBrandShape.swift`，无 app 依赖、可独立测试）+ 品牌视图层（`ProviderBrandIcon.swift`）；`ProviderAdapter` 增加 `brandIcon` 属性（协议扩展默认 nil，自定义供应商不受影响）；两个 UI 调用点换成 `ProviderBrandIconView`。

**Tech Stack:** SwiftUI / AppKit，swiftc 直编（无 SPM、无 asset catalog）。

**Spec:** `docs/superpowers/specs/2026-07-18-brand-icons-design.md`

**Path data sources（已核实）：**
- deepseek / minimax / opencode：simple-icons 官方 SVG（viewBox 24×24）
- openrouter：`https://openrouter.ai/brand/v2/openrouter-glyph-light.svg`（viewBox 401.4×293.7）
- siliconflow：`https://siliconflow.cn/logo-new.svg` 的符号路径（bbox 53.03×25.36）
- volcano：`volcengine.com` 官方 logo SVG 的 5 条峰路径（cls-3 青 / cls-4 蓝；符号 bbox 84.27×75）
- codex：Wikimedia `OpenAI_Logo.svg` 的结形路径（bbox x -4.57..324.58, y -0.14..320.14）

---

### Task 1: SVG 路径解析器 + 品牌路径数据（SVGBrandShape.swift）

**Files:**
- Create: `Sources/TokenBar/Views/SVGBrandShape.swift`
- Create (临时, 验证后删除): `/tmp/svg_harness/main.swift`

- [ ] **Step 1: 创建 SVGBrandShape.swift**

```swift
import SwiftUI

/// Parses the `d` attribute of an SVG `<path>` into a SwiftUI `Path`.
/// Supports M L H V C S A Z (absolute and relative) — the command set used
/// by the brand glyphs in `BrandGlyphPaths`.
public enum SVGPathParser {

    public static func parse(_ data: String) -> Path {
        let tokens = tokenize(data)
        var path = Path()
        var i = 0
        var cmd = "M"
        var cur = CGPoint.zero
        var start = CGPoint.zero
        var prevCtrl2: CGPoint?

        func number() -> CGFloat {
            defer { i += 1 }
            return CGFloat(Double(tokens[i]) ?? 0)
        }

        while i < tokens.count {
            let consumed = i
            if tokens[i].count == 1, tokens[i].first!.isLetter {
                cmd = tokens[i]
                i += 1
            }
            let rel = cmd == cmd.lowercased()
            switch cmd.uppercased() {
            case "M":
                var p = CGPoint(x: number(), y: number())
                if rel { p = p + cur }
                path.move(to: p)
                cur = p; start = p
                cmd = rel ? "l" : "L" // implicit lineto after moveto
                prevCtrl2 = nil
            case "L":
                var p = CGPoint(x: number(), y: number())
                if rel { p = p + cur }
                path.addLine(to: p)
                cur = p
                prevCtrl2 = nil
            case "H":
                var x = number()
                if rel { x += cur.x }
                cur = CGPoint(x: x, y: cur.y)
                path.addLine(to: cur)
                prevCtrl2 = nil
            case "V":
                var y = number()
                if rel { y += cur.y }
                cur = CGPoint(x: cur.x, y: y)
                path.addLine(to: cur)
                prevCtrl2 = nil
            case "C":
                var c1 = CGPoint(x: number(), y: number())
                var c2 = CGPoint(x: number(), y: number())
                var p = CGPoint(x: number(), y: number())
                if rel { c1 = c1 + cur; c2 = c2 + cur; p = p + cur }
                path.addCurve(to: p, control1: c1, control2: c2)
                prevCtrl2 = c2
                cur = p
            case "S":
                let c1 = prevCtrl2.map { CGPoint(x: 2 * cur.x - $0.x, y: 2 * cur.y - $0.y) } ?? cur
                var c2 = CGPoint(x: number(), y: number())
                var p = CGPoint(x: number(), y: number())
                if rel { c2 = c2 + cur; p = p + cur }
                path.addCurve(to: p, control1: c1, control2: c2)
                prevCtrl2 = c2
                cur = p
            case "A":
                let rx = number(), ry = number()
                let rotation = number()
                let largeArc = number() != 0
                let sweep = number() != 0
                var p = CGPoint(x: number(), y: number())
                if rel { p = p + cur }
                addArc(to: &path, from: cur, rx: rx, ry: ry,
                       xAxisRotationDeg: rotation, largeArc: largeArc, sweep: sweep, end: p)
                cur = p
                prevCtrl2 = nil // S-after-A does not occur in our glyphs
            case "Z":
                path.closeSubpath()
                cur = start
                prevCtrl2 = nil
            default:
                break
            }
            if i == consumed { i += 1 } // never stall on malformed input
        }
        return path
    }

    private static func tokenize(_ data: String) -> [String] {
        // Commas and whitespace are separators: they simply never match.
        let pattern = #"[-+]?(?:\d*\.\d+|\d+)(?:[eE][-+]?\d+)?|[AaCcHhLlMmSsVvZz]"#
        let regex = try! NSRegularExpression(pattern: pattern)
        let range = NSRange(data.startIndex..<data.endIndex, in: data)
        return regex.matches(in: data, range: range).compactMap {
            Range($0.range, in: data).map { String(data[$0]) }
        }
    }

    /// SVG elliptical arc (spec F.6) converted to cubic Bézier segments.
    private static func addArc(to path: inout Path, from p0: CGPoint, rx: CGFloat, ry: CGFloat,
                               xAxisRotationDeg: CGFloat, largeArc: Bool, sweep: Bool, end p1: CGPoint) {
        var rx = abs(rx), ry = abs(ry)
        guard p0 != p1 else { return }
        guard rx > .ulpOfOne, ry > .ulpOfOne else {
            path.addLine(to: p1)
            return
        }
        let phi = xAxisRotationDeg * .pi / 180
        let cosPhi = cos(phi), sinPhi = sin(phi)
        // F.6.5.1
        let dx = (p0.x - p1.x) / 2, dy = (p0.y - p1.y) / 2
        let x1p = cosPhi * dx + sinPhi * dy
        let y1p = -sinPhi * dx + cosPhi * dy
        // F.6.6 out-of-range radius correction
        let lambda = x1p * x1p / (rx * rx) + y1p * y1p / (ry * ry)
        if lambda > 1 {
            let s = sqrt(lambda)
            rx *= s; ry *= s
        }
        // F.6.5.2 center in prime coordinates
        let sign: CGFloat = largeArc == sweep ? -1 : 1
        let num = rx * rx * ry * ry - rx * rx * y1p * y1p - ry * ry * x1p * x1p
        let den = rx * rx * y1p * y1p + ry * ry * x1p * x1p
        let co = sign * sqrt(max(0, num / den))
        let cxp = co * rx * y1p / ry
        let cyp = -co * ry * x1p / rx
        // F.6.5.3 center in absolute coordinates
        let cx = cosPhi * cxp - sinPhi * cyp + (p0.x + p1.x) / 2
        let cy = sinPhi * cxp + cosPhi * cyp + (p0.y + p1.y) / 2
        // F.6.5.4–5.5 start/sweep angles
        func angle(_ u: CGPoint, _ v: CGPoint) -> CGFloat {
            let dot = u.x * v.x + u.y * v.y
            let len = sqrt((u.x * u.x + u.y * u.y) * (v.x * v.x + v.y * v.y))
            var a = acos(max(-1, min(1, dot / len)))
            if u.x * v.y - u.y * v.x < 0 { a = -a }
            return a
        }
        let v1 = CGPoint(x: (x1p - cxp) / rx, y: (y1p - cyp) / ry)
        let v2 = CGPoint(x: (-x1p - cxp) / rx, y: (-y1p - cyp) / ry)
        let theta1 = angle(CGPoint(x: 1, y: 0), v1)
        var delta = angle(v1, v2).truncatingRemainder(dividingBy: 2 * .pi)
        if !sweep, delta > 0 { delta -= 2 * .pi }
        if sweep, delta < 0 { delta += 2 * .pi }
        // Split into ≤90° segments; each approximated by one cubic Bézier.
        func point(_ t: CGFloat) -> CGPoint {
            CGPoint(x: cx + rx * cos(t) * cosPhi - ry * sin(t) * sinPhi,
                    y: cy + rx * cos(t) * sinPhi + ry * sin(t) * cosPhi)
        }
        func derivative(_ t: CGFloat) -> CGPoint {
            CGPoint(x: -rx * sin(t) * cosPhi - ry * cos(t) * sinPhi,
                    y: -rx * sin(t) * sinPhi + ry * cos(t) * cosPhi)
        }
        let segments = max(1, Int(ceil(abs(delta) / (.pi / 2))))
        let step = delta / CGFloat(segments)
        for n in 0..<segments {
            let t1 = theta1 + CGFloat(n) * step
            let t2 = t1 + step
            let alpha = 4 / 3 * tan((t2 - t1) / 4)
            let c1 = point(t1) + derivative(t1) * alpha
            let c2 = point(t2) - derivative(t2) * alpha
            path.addCurve(to: point(t2), control1: c1, control2: c2)
        }
    }
}

private func + (a: CGPoint, b: CGPoint) -> CGPoint { CGPoint(x: a.x + b.x, y: a.y + b.y) }
private func - (a: CGPoint, b: CGPoint) -> CGPoint { CGPoint(x: a.x - b.x, y: a.y - b.y) }
private func * (a: CGPoint, s: CGFloat) -> CGPoint { CGPoint(x: a.x * s, y: a.y * s) }

/// A Shape that renders an SVG path string, aspect-fit and centered into `rect`.
public struct SVGBrandShape: Shape {
    public let pathData: String
    public let viewBox: CGRect

    public init(pathData: String, viewBox: CGRect) {
        self.pathData = pathData
        self.viewBox = viewBox
    }

    public func path(in rect: CGRect) -> Path {
        let scale = min(rect.width / viewBox.width, rect.height / viewBox.height)
        var t = CGAffineTransform.identity
        t = t.translatedBy(x: rect.minX + (rect.width - viewBox.width * scale) / 2,
                           y: rect.minY + (rect.height - viewBox.height * scale) / 2)
        t = t.scaledBy(x: scale, y: scale)
        t = t.translatedBy(x: -viewBox.minX, y: -viewBox.minY)
        return SVGPathParser.parse(pathData).applying(t)
    }
}

/// Official brand glyph path data (see plan header for sources).
public enum BrandGlyphPaths {
    // DeepSeek whale — simple-icons `deepseek`, viewBox 24×24.
    public static let deepSeek = #"M23.748 4.651c-.254-.124-.364.113-.512.233-.051.04-.094.09-.137.137-.372.397-.806.657-1.373.626-.829-.046-1.537.214-2.163.848-.133-.782-.575-1.248-1.247-1.548-.352-.155-.708-.311-.955-.65-.172-.24-.219-.509-.305-.774-.055-.16-.11-.323-.293-.35-.2-.031-.278.136-.356.276-.313.572-.434 1.202-.422 1.84.027 1.436.633 2.58 1.838 3.393.137.094.172.187.129.323-.082.28-.18.553-.266.833-.055.179-.137.218-.328.14a5.5 5.5 0 0 1-1.737-1.179c-.857-.828-1.631-1.743-2.597-2.46a12 12 0 0 0-.689-.47c-.985-.957.13-1.743.387-1.836.27-.098.094-.433-.778-.428-.872.003-1.67.295-2.687.685a3 3 0 0 1-.465.136 9.6 9.6 0 0 0-2.883-.101c-1.885.21-3.39 1.1-4.497 2.622C.082 8.776-.231 10.854.152 13.02c.403 2.284 1.568 4.175 3.36 5.653 1.857 1.533 3.997 2.284 6.438 2.14 1.482-.085 3.132-.284 4.994-1.86.47.234.962.328 1.78.398.629.058 1.235-.031 1.705-.129.735-.155.684-.836.418-.961-2.155-1.004-1.682-.595-2.112-.926 1.095-1.295 2.768-3.598 3.284-6.733.05-.346.115-.834.108-1.114-.004-.171.035-.238.23-.257a4.2 4.2 0 0 0 1.545-.475c1.397-.763 1.96-2.016 2.093-3.517.02-.23-.004-.467-.247-.588M11.58 18.168c-2.088-1.642-3.101-2.183-3.52-2.16-.39.024-.32.472-.234.763.09.288.207.487.371.74.114.167.192.416-.113.603-.673.416-1.842-.14-1.897-.168-1.361-.801-2.5-1.86-3.301-3.306-.775-1.393-1.225-2.888-1.299-4.482-.02-.385.094-.522.477-.592a4.7 4.7 0 0 1 1.53-.038c2.131.311 3.946 1.264 5.467 2.774.868.86 1.525 1.887 2.202 2.89.72 1.066 1.494 2.082 2.48 2.915.348.291.626.513.892.677-.802.09-2.14.109-3.055-.615zm1.001-6.44a.306.306 0 0 1 .415-.287.3.3 0 0 1 .113.074.3.3 0 0 1 .086.214c0 .17-.136.307-.308.307a.303.303 0 0 1-.306-.307m3.11 1.596c-.2.081-.4.151-.591.16a1.25 1.25 0 0 1-.798-.254c-.274-.23-.47-.358-.551-.758a1.7 1.7 0 0 1 .015-.588c.07-.327-.007-.537-.238-.727-.188-.156-.426-.199-.689-.199a.6.6 0 0 1-.254-.078.253.253 0 0 1-.114-.358 1 1 0 0 1 .192-.21c.356-.202.767-.136 1.146.016.352.144.618.408 1.001.782.392.451.462.576.685.915.176.264.336.536.446.848.066.194-.02.353-.25.45"#
    public static let deepSeekBox = CGRect(x: 0, y: 0, width: 24, height: 24)

    // MiniMax waveform — simple-icons `minimax`, viewBox 24×24.
    public static let miniMax = #"M11.43 3.92a.86.86 0 1 0-1.718 0v14.236a1.999 1.999 0 0 1-3.997 0V9.022a.86.86 0 1 0-1.718 0v3.87a1.999 1.999 0 0 1-3.997 0V11.49a.57.57 0 0 1 1.139 0v1.404a.86.86 0 0 0 1.719 0V9.022a1.999 1.999 0 0 1 3.997 0v9.134a.86.86 0 0 0 1.719 0V3.92a1.998 1.998 0 1 1 3.996 0v11.788a.57.57 0 1 1-1.139 0zm10.572 3.105a2 2 0 0 0-1.999 1.997v7.63a.86.86 0 0 1-1.718 0V3.923a1.999 1.999 0 0 0-3.997 0v16.16a.86.86 0 0 1-1.719 0V18.08a.57.57 0 1 0-1.138 0v2a1.998 1.998 0 0 0 3.996 0V3.92a.86.86 0 0 1 1.719 0v12.73a1.999 1.999 0 0 0 3.996 0V9.023a.86.86 0 1 1 1.72 0v6.686a.57.57 0 0 0 1.138 0V9.022a2 2 0 0 0-1.998-1.997"#
    public static let miniMaxBox = CGRect(x: 0, y: 0, width: 24, height: 24)

    // opencode square-O — simple-icons `opencode`, viewBox 24×24.
    public static let openCode = #"M22 24H2V0h20zM17 4.8H7v14.4h10z"#
    public static let openCodeBox = CGRect(x: 0, y: 0, width: 24, height: 24)

    // OpenRouter "OR" monogram (2025) — openrouter.ai/brand/v2 glyph, viewBox 401.4×293.7.
    public static let openRouter = #"M303.9475,17.19926c42.79734,0,77.48933,34.69327,77.48933,77.48933s-34.69199,77.48933-77.48933,77.48933l76.86166,76.86244c9.76367,9.76313,2.84903,26.45667-10.95697,26.45667h-220.88335c-71.32686,0-129.14889-57.82202-129.14889-129.14889S77.64197,17.19926,148.96884,17.19926h154.97866ZM148.96884,68.85881c-42.79607,0-77.48933,34.69327-77.48933,77.48933s34.69327,77.48933,77.48933,77.48933,77.48933-34.69327,77.48933-77.48933-34.69327-77.48933-77.48933-77.48933Z"#
    public static let openRouterBox = CGRect(x: 0, y: 0, width: 401.4, height: 293.7)

    // SiliconFlow zigzag-S — siliconflow.cn/logo-new.svg symbol path (bbox 53.03×25.36).
    public static let siliconFlow = #"M50.7172 0H27.6622C26.3877 0 25.3586 1.03397 25.3586 2.30358V9.21911C25.3586 10.4935 24.3294 11.5227 23.055 11.5227H2.30357C1.02914 11.5227 0 12.5567 0 13.8263V23.0502C0 24.3246 1.03395 25.3538 2.30357 25.3538H25.3586C26.633 25.3538 27.6622 24.3198 27.6622 23.0502V16.1347C27.6622 14.8602 28.6913 13.8311 29.9657 13.8311H50.7172C51.9916 13.8311 53.0207 12.7971 53.0207 11.5275V2.30358C53.0207 1.02916 51.9868 0 50.7172 0Z"#
    public static let siliconFlowBox = CGRect(x: 0, y: 0, width: 53.03, height: 25.36)

    // Volcano Engine peaks — volcengine.com official logo, symbol bbox 84.27×75.
    // Paint order matters: all cyan peaks first, then all blue on top (matches
    // the original document order where blue paths always paint after the cyan
    // ones they overlap).
    public static let volcanoCyan = #"M34.82,28.93l-14.97,46.07h32.16l-14.97-46.07c-.35-1.08-1.88-1.08-2.23,0Z M12.83,42.36c-.35-1.08-1.88-1.08-2.23,0L0,75h9.42l7.01-21.57-3.59-11.06Z M71.73,36.43c-.35-1.08-1.88-1.08-2.23,0l-3.55,10.94,8.98,27.63h9.34l-12.53-38.57Z"#
    public static let volcanoBlue = #"M29.52,20c-.35-1.08-1.88-1.08-2.23,0l-17.87,55h10.43l13.77-42.37-4.1-12.63Z M50.82.81c-.35-1.08-1.88-1.08-2.23,0l-10.34,31.82,13.77,42.37h22.9L50.82.81Z"#
    public static let volcanoBox = CGRect(x: 0, y: 0, width: 84.27, height: 75)

    // OpenAI blossom knot — Wikimedia OpenAI_Logo.svg knot path (bbox below).
    public static let codex = #"m297.06 130.97c7.26-21.79 4.76-45.66-6.85-65.48-17.46-30.4-52.56-46.04-86.84-38.68-15.25-17.18-37.16-26.95-60.13-26.81-35.04-.08-66.13 22.48-76.91 55.82-22.51 4.61-41.94 18.7-53.31 38.67-17.59 30.32-13.58 68.54 9.92 94.54-7.26 21.79-4.76 45.66 6.85 65.48 17.46 30.4 52.56 46.04 86.84 38.68 15.24 17.18 37.16 26.95 60.13 26.8 35.06.09 66.16-22.49 76.94-55.86 22.51-4.61 41.94-18.7 53.31-38.67 17.57-30.32 13.55-68.51-9.94-94.51zm-120.28 168.11c-14.03.02-27.62-4.89-38.39-13.88.49-.26 1.34-.73 1.89-1.07l63.72-36.8c3.26-1.85 5.26-5.32 5.24-9.07v-89.83l26.93 15.55c.29.14.48.42.52.74v74.39c-.04 33.08-26.83 59.9-59.91 59.97zm-128.84-55.03c-7.03-12.14-9.56-26.37-7.15-40.18.47.28 1.3.79 1.89 1.13l63.72 36.8c3.23 1.89 7.23 1.89 10.47 0l77.79-44.92v31.1c.02.32-.13.63-.38.83l-64.41 37.19c-28.69 16.52-65.33 6.7-81.92-21.95zm-16.77-139.09c7-12.16 18.05-21.46 31.21-26.29 0 .55-.03 1.52-.03 2.2v73.61c-.02 3.74 1.98 7.21 5.23 9.06l77.79 44.91-26.93 15.55c-.27.18-.61.21-.91.08l-64.42-37.22c-28.63-16.58-38.45-53.21-21.95-81.89zm221.26 51.49-77.79-44.92 26.93-15.54c.27-.18.61-.21.91-.08l64.42 37.19c28.68 16.57 38.51 53.26 21.94 81.94-7.01 12.14-18.05 21.44-31.2 26.28v-75.81c.03-3.74-1.96-7.2-5.2-9.06zm26.8-40.34c-.47-.29-1.3-.79-1.89-1.13l-63.72-36.8c-3.23-1.89-7.23-1.89-10.47 0l-77.79 44.92v-31.1c-.02-.32.13-.63.38-.83l64.41-37.16c28.69-16.55 65.37-6.7 81.91 22 6.99 12.12 9.52 26.31 7.15 40.1zm-168.51 55.43-26.94-15.55c-.29-.14-.48-.42-.52-.74v-74.39c.02-33.12 26.89-59.96 60.01-59.94 14.01 0 27.57 4.92 38.34 13.88-.49.26-1.33.73-1.89 1.07l-63.72 36.8c-3.26 1.85-5.26 5.31-5.24 9.06l-.04 89.79zm14.63-31.54 34.65-20.01 34.65 20v40.01l-34.65 20-34.65-20z"#
    public static let codexBox = CGRect(x: 2.13, y: 0, width: 315.75, height: 320)
}
```

- [ ] **Step 2: 写临时验证 harness**

`/tmp/svg_harness/main.swift`:

```swift
import SwiftUI

var failures = 0
func check(_ name: String, _ rect: CGRect, _ exp: CGRect, tol: CGFloat = 1.5) {
    let ok = abs(rect.minX - exp.minX) <= tol && abs(rect.minY - exp.minY) <= tol
        && abs(rect.width - exp.width) <= tol && abs(rect.height - exp.height) <= tol
    print("\(ok ? "PASS" : "FAIL") \(name): got \(rect) expect≈\(exp)")
    if !ok { failures += 1 }
}

check("openCode", SVGPathParser.parse(BrandGlyphPaths.openCode).boundingRect,
      CGRect(x: 2, y: 0, width: 20, height: 24))
check("deepSeek", SVGPathParser.parse(BrandGlyphPaths.deepSeek).boundingRect,
      CGRect(x: 0, y: 2.8, width: 24, height: 17.2), tol: 2.5)
check("miniMax", SVGPathParser.parse(BrandGlyphPaths.miniMax).boundingRect,
      CGRect(x: 0, y: 1.92, width: 24, height: 20.16), tol: 0.6)
check("openRouter", SVGPathParser.parse(BrandGlyphPaths.openRouter).boundingRect,
      CGRect(x: 19.82, y: 17.2, width: 365.56, height: 258.3), tol: 5)
check("siliconFlow", SVGPathParser.parse(BrandGlyphPaths.siliconFlow).boundingRect,
      CGRect(x: 0, y: 0, width: 53.03, height: 25.36))
check("volcanoCyan", SVGPathParser.parse(BrandGlyphPaths.volcanoCyan).boundingRect,
      CGRect(x: 0, y: 28.12, width: 84.27, height: 46.88), tol: 0.6)
check("volcanoBlue", SVGPathParser.parse(BrandGlyphPaths.volcanoBlue).boundingRect,
      CGRect(x: 9.42, y: 0, width: 65.5, height: 75), tol: 0.6)
check("codex", SVGPathParser.parse(BrandGlyphPaths.codex).boundingRect,
      CGRect(x: 2.13, y: 0, width: 315.75, height: 320), tol: 3)

// Shape 变换：viewBox 必须等比缩放并居中进目标 rect
let shapeRect = SVGBrandShape(pathData: BrandGlyphPaths.openCode, viewBox: BrandGlyphPaths.openCodeBox)
    .path(in: CGRect(x: 0, y: 0, width: 13, height: 13)).boundingRect
print("shape openCode in 13×13 -> \(shapeRect)")
if shapeRect.width < 9 || shapeRect.height < 11 || shapeRect.maxX > 13.5 {
    print("FAIL shape transform"); failures += 1
} else {
    print("PASS shape transform")
}

exit(failures == 0 ? 0 : 1)
```

注意：deepSeek/minimax 的 `boundingRect` 含曲线控制点，容差给大。

- [ ] **Step 3: 运行 harness 验证**

```bash
mkdir -p /tmp/svg_harness
# (写入 main.swift 后)
swiftc -sdk "$(xcrun --show-sdk-path)" -target "$(uname -m)-apple-macos14.0" \
  Sources/TokenBar/Views/SVGBrandShape.swift /tmp/svg_harness/main.swift \
  -o /tmp/svg_harness/svgtest && /tmp/svg_harness/svgtest
```

Expected: 全部 `PASS`，exit 0。若 bbox 偏差大，检查路径数据复制是否完整。

- [ ] **Step 4: Commit**

```bash
git add Sources/TokenBar/Views/SVGBrandShape.swift
git commit -m "feat: add SVG path parser and brand glyph data"
```

---

### Task 2: 品牌图标视图（ProviderBrandIcon.swift）

**Files:**
- Create: `Sources/TokenBar/Views/ProviderBrandIcon.swift`

- [ ] **Step 1: 创建 ProviderBrandIcon.swift**

```swift
import AppKit
import SwiftUI

/// Real brand glyphs for built-in providers. Drawn as vector shapes from
/// official SVG path data; colors adapted per brand (see design spec).
public enum BrandIcon: Sendable {
    case deepSeek
    case siliconFlow
    case volcano
    case miniMax
    case openRouter
    case openCode
    case codex
}

extension NSColor {
    convenience init(hex: UInt32) {
        self.init(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
                  green: CGFloat((hex >> 8) & 0xFF) / 255,
                  blue: CGFloat(hex & 0xFF) / 255,
                  alpha: 1)
    }
}

extension Color {
    init(hex: UInt32) { self.init(nsColor: NSColor(hex: hex)) }

    static func adaptive(light: UInt32, dark: UInt32) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            return NSColor(hex: isDark ? dark : light)
        })
    }
}

/// Renders a provider's real brand icon, falling back to its SF Symbol
/// (`iconSystemName`) for custom providers.
public struct ProviderBrandIconView: View {
    public let provider: any ProviderAdapter
    public let size: CGFloat

    public init(provider: any ProviderAdapter, size: CGFloat = 13) {
        self.provider = provider
        self.size = size
    }

    public var body: some View {
        Group {
            if let brand = provider.brandIcon {
                content(for: brand)
            } else {
                Image(systemName: provider.iconSystemName)
                    .font(.system(size: size))
            }
        }
        .accessibilityLabel(provider.displayName)
    }

    @ViewBuilder
    private func content(for brand: BrandIcon) -> some View {
        switch brand {
        case .deepSeek:
            SVGBrandShape(pathData: BrandGlyphPaths.deepSeek, viewBox: BrandGlyphPaths.deepSeekBox)
                .fill(Color(hex: 0x5786FE))
                .frame(width: size, height: size)
        case .siliconFlow:
            SVGBrandShape(pathData: BrandGlyphPaths.siliconFlow, viewBox: BrandGlyphPaths.siliconFlowBox)
                .fill(Color(hex: 0x6E29F5))
                .frame(width: size, height: size)
        case .volcano:
            ZStack {
                SVGBrandShape(pathData: BrandGlyphPaths.volcanoCyan, viewBox: BrandGlyphPaths.volcanoBox)
                    .fill(Color(hex: 0x00DCFF))
                SVGBrandShape(pathData: BrandGlyphPaths.volcanoBlue, viewBox: BrandGlyphPaths.volcanoBox)
                    .fill(Color(hex: 0x006AFF))
            }
            .frame(width: size, height: size)
        case .miniMax:
            SVGBrandShape(pathData: BrandGlyphPaths.miniMax, viewBox: BrandGlyphPaths.miniMaxBox)
                .fill(LinearGradient(colors: [Color(hex: 0xE4177F), Color(hex: 0xE73562), Color(hex: 0xE94E4A)],
                                     startPoint: .leading, endPoint: .trailing))
                .frame(width: size, height: size)
        case .openRouter:
            SVGBrandShape(pathData: BrandGlyphPaths.openRouter, viewBox: BrandGlyphPaths.openRouterBox)
                .fill(Color.adaptive(light: 0x7624F4, dark: 0xC8FF00))
                .frame(width: size, height: size)
        case .openCode:
            SVGBrandShape(pathData: BrandGlyphPaths.openCode, viewBox: BrandGlyphPaths.openCodeBox)
                .fill(Color.primary)
                .frame(width: size, height: size)
        case .codex:
            SVGBrandShape(pathData: BrandGlyphPaths.codex, viewBox: BrandGlyphPaths.codexBox)
                .fill(Color.primary)
                .frame(width: size, height: size)
        }
    }
}
```

- [ ] **Step 2: 编译验证**

Run: `./scripts/build.sh`
Expected: `Built: build/TokenBar.app ...`（此刻 `brandIcon` 协议属性还不存在，`ProviderBrandIconView` 里 `provider.brandIcon` 会编译失败——属预期，Task 3 补上协议后通过。若不想见红，可先完成 Task 3 Step 1 再 build。）

- [ ] **Step 3: Commit**（与 Task 3 一起通过编译后提交，或确认仅缺协议符号时先提交）

```bash
git add Sources/TokenBar/Views/ProviderBrandIcon.swift
git commit -m "feat: add brand icon view with per-brand colors"
```

---

### Task 3: 协议属性 + 7 个适配器接线

**Files:**
- Modify: `Sources/TokenBar/Adapters/Core/ProviderAdapter.swift`（协议 + 默认实现）
- Modify: `Sources/TokenBar/Adapters/Core/WebViewAdapter.swift:17-36`（存储属性 + init 参数）
- Modify: `Sources/TokenBar/Adapters/MinimaxAdapter.swift:123-127`
- Modify: `Sources/TokenBar/Adapters/OpenRouterAdapter.swift`（super.init 处）
- Modify: `Sources/TokenBar/Adapters/OpenCodeGoAdapter.swift`（super.init 处）
- Modify: `Sources/TokenBar/Adapters/DeepSeekAdapter.swift:39`
- Modify: `Sources/TokenBar/Adapters/SiliconFlowAdapter.swift:32`
- Modify: `Sources/TokenBar/Adapters/VolcanoEngineAdapter.swift:32`
- Modify: `Sources/TokenBar/Adapters/CodexAdapter.swift:11`

- [ ] **Step 1: ProviderAdapter.swift 协议**

`ProviderAdapter` 协议内 `iconSystemName` 后加：

```swift
    /// Real brand glyph for built-in providers; nil → UI falls back to `iconSystemName`.
    var brandIcon: BrandIcon? { get }
```

协议定义之后加默认实现（自定义供应商、HTTPAdapter、测试 Stub 自动获得 nil）：

```swift
public extension ProviderAdapter {
    var brandIcon: BrandIcon? { nil }
}
```

- [ ] **Step 2: WebViewAdapter.swift**

`public let iconSystemName: String`（line 19）后加：

```swift
    public let brandIcon: BrandIcon?
```

init 改为（默认参数保持其他调用点兼容）：

```swift
    public init(id: String, displayName: String, iconSystemName: String,
                loginURL: URL, harvestScript: String, brandIcon: BrandIcon? = nil) {
        self.id = id; self.displayName = displayName; self.iconSystemName = iconSystemName
        self.loginURL = loginURL; self.harvestScript = harvestScript
        self.brandIcon = brandIcon
    }
```

- [ ] **Step 3: 三个 WebViewAdapter 子类传 brandIcon**

MinimaxAdapter.swift super.init：

```swift
        super.init(id: "minimax",
                   displayName: "MiniMax",
                   iconSystemName: "sparkles",
                   loginURL: URL(string: "https://platform.minimaxi.com/console/usage")!,
                   harvestScript: js,
                   brandIcon: .miniMax)
```

OpenRouterAdapter.swift super.init：

```swift
        super.init(id: "openrouter",
                   displayName: "OpenRouter",
                   iconSystemName: "arrow.triangle.branch",
                   loginURL: URL(string: "https://openrouter.ai/settings/credits")!,
                   harvestScript: js,
                   brandIcon: .openRouter)
```

OpenCodeGoAdapter.swift super.init：

```swift
        super.init(id: "opencode-go", displayName: "opencode go",
                   iconSystemName: "bolt.fill",
                   loginURL: URL(string: "https://opencode.ai/workspace/wrk_01KVB7CEDBFN8VF6FYA2DJ1GR3/go")!,
                   harvestScript: js,
                   brandIcon: .openCode)
```

- [ ] **Step 4: 四个 struct 适配器加计算属性**

DeepSeekAdapter.swift（`iconSystemName` 后）：

```swift
    public var brandIcon: BrandIcon? { .deepSeek }
```

SiliconFlowAdapter.swift：

```swift
    public var brandIcon: BrandIcon? { .siliconFlow }
```

VolcanoEngineAdapter.swift：

```swift
    public var brandIcon: BrandIcon? { .volcano }
```

CodexAdapter.swift：

```swift
    public var brandIcon: BrandIcon? { .codex }
```

- [ ] **Step 5: 编译验证**

Run: `./scripts/build.sh`
Expected: `Built: build/TokenBar.app (v…)`，无错误。

- [ ] **Step 6: Commit**

```bash
git add Sources/TokenBar/Adapters
git commit -m "feat: wire brand icons into built-in provider adapters"
```

---

### Task 4: UI 调用点替换

**Files:**
- Modify: `Sources/TokenBar/Views/ProviderSectionView.swift:136`
- Modify: `Sources/TokenBar/Views/PopoverContentView.swift:236`

- [ ] **Step 1: ProviderSectionView providerHeader**

把

```swift
            if !compactBalance {
                Image(systemName: provider.iconSystemName)
            }
```

改为

```swift
            if !compactBalance {
                ProviderBrandIconView(provider: provider, size: 13)
            }
```

- [ ] **Step 2: PopoverContentView ProviderDragPreview**

把

```swift
        HStack(spacing: 8) {
            Image(systemName: provider.iconSystemName)
            Text(provider.displayName)
                .font(.headline)
        }
```

里的 `Image(systemName: provider.iconSystemName)` 改为

```swift
            ProviderBrandIconView(provider: provider, size: 14)
```

- [ ] **Step 3: 编译验证**

Run: `./scripts/build.sh`
Expected: 构建成功。

- [ ] **Step 4: Commit**

```bash
git add Sources/TokenBar/Views/ProviderSectionView.swift Sources/TokenBar/Views/PopoverContentView.swift
git commit -m "feat: render real brand icons in provider list and drag preview"
```

---

### Task 5: 持久化测试（休眠 XCTest，镜像 harness 断言）

**Files:**
- Create: `tests/TokenBarTests/BrandIconTests.swift`

说明：仓库当前无 Package.swift，测试无运行器（既有测试同样如此）。断言与 Task 1 harness 一致，已实际验证过；待 SPM 环境恢复即可运行。

- [ ] **Step 1: 创建测试文件**

```swift
import XCTest
@testable import TokenBar

final class BrandIconTests: XCTestCase {
    func test_allBuiltInProviders_haveBrandIcons() {
        for adapter in ProvidersRegistry.default.adapters {
            XCTAssertNotNil(adapter.brandIcon, "\(adapter.id) missing brandIcon")
        }
    }

    func test_parser_openCodeFrame_bbox() {
        let rect = SVGPathParser.parse(BrandGlyphPaths.openCode).boundingRect
        XCTAssertEqual(rect.minX, 2, accuracy: 0.5)
        XCTAssertEqual(rect.minY, 0, accuracy: 0.5)
        XCTAssertEqual(rect.width, 20, accuracy: 0.5)
        XCTAssertEqual(rect.height, 24, accuracy: 0.5)
    }

    func test_parser_allGlyphs_haveFiniteNonEmptyBounds() {
        let glyphs: [(String, CGRect)] = [
            ("deepSeek", BrandGlyphPaths.deepSeekBox),
            ("miniMax", BrandGlyphPaths.miniMaxBox),
            ("openCode", BrandGlyphPaths.openCodeBox),
            ("openRouter", BrandGlyphPaths.openRouterBox),
            ("siliconFlow", BrandGlyphPaths.siliconFlowBox),
            ("volcano", BrandGlyphPaths.volcanoBox),
            ("codex", BrandGlyphPaths.codexBox),
        ]
        let paths: [String: String] = [
            "deepSeek": BrandGlyphPaths.deepSeek,
            "miniMax": BrandGlyphPaths.miniMax,
            "openCode": BrandGlyphPaths.openCode,
            "openRouter": BrandGlyphPaths.openRouter,
            "siliconFlow": BrandGlyphPaths.siliconFlow,
            "volcano": BrandGlyphPaths.volcanoCyan + BrandGlyphPaths.volcanoBlue,
            "codex": BrandGlyphPaths.codex,
        ]
        for (name, _) in glyphs {
            let rect = SVGPathParser.parse(paths[name]!).boundingRect
            XCTAssertTrue(rect.isFinite, name)
            XCTAssertGreaterThan(rect.width, 0, name)
            XCTAssertGreaterThan(rect.height, 0, name)
        }
    }
}
```

- [ ] **Step 2: Commit**

```bash
git add tests/TokenBarTests/BrandIconTests.swift
git commit -m "test: add brand icon parser tests"
```

---

### Task 6: 全量验证 + PR merge

- [ ] **Step 1: 全量构建**

Run: `./scripts/build.sh`
Expected: `Built: build/TokenBar.app (vX.Y.Z build N)`，secret scan 通过。

- [ ] **Step 2: Push + 创建 PR**

```bash
git push -u origin agent/brand-icons
gh pr create --base agent/custom-field-picker \
  --title "feat: real brand icons for built-in providers" \
  --body "用官方 SVG 路径数据为 7 个内置供应商绘制矢量品牌图标，替换 SF Symbol 占位图标。配色按品牌适配（品牌色/渐变/深浅色自适应），自定义供应商不受影响。设计：docs/superpowers/specs/2026-07-18-brand-icons-design.md"
```

- [ ] **Step 3: Squash merge + 清理**

```bash
gh pr merge --squash --delete-branch
git checkout agent/custom-field-picker && git pull
```

- [ ] **Step 4: 请用户运行 App 肉眼确认**（浅色 + 深色模式下 7 个图标形态与配色）

---

## Self-Review

- Spec 覆盖：7 品牌图形+配色 → Task 1/2；协议+适配器 → Task 3；两个调用点 → Task 4；验证 → Task 1 harness + Task 6。✓
- 占位符：无；所有步骤含完整代码/命令。✓
- 类型一致：`BrandIcon` 枚举 case（deepSeek/siliconFlow/volcano/miniMax/openRouter/openCode/codex）在 Task 2 定义，Task 3 引用一致；`BrandGlyphPaths.*`/`SVGBrandShape`/`SVGPathParser` 命名全篇一致；`ProviderBrandIconView(provider:size:)` 与调用点一致。✓
