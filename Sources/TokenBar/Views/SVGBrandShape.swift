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

/// Official brand glyph path data. Sources:
/// deepseek/minimax/opencode: simple-icons; openrouter: openrouter.ai/brand/v2;
/// siliconflow: siliconflow.cn/logo-new.svg; volcano: volcengine.com logo SVG;
/// codex: Wikimedia OpenAI_Logo.svg knot path.
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
