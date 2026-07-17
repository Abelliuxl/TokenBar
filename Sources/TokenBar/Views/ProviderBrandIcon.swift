import AppKit
import SwiftUI

/// Real brand glyphs for built-in providers. Drawn as vector shapes from
/// official SVG path data; colors adapted per brand (see design spec
/// `docs/superpowers/specs/2026-07-18-brand-icons-design.md`).
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
