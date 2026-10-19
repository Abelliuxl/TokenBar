import SwiftUI

public struct QuotaRowView: View {
    let quota: Quota
    public init(quota: Quota) { self.quota = quota }

    public var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            if quota.showsProgressBar {
                usageRow
            } else {
                balanceRow
            }
        }
        .padding(.vertical, 2)
    }

    private var balanceRow: some View {
        HStack {
            Text(quota.label)
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
            Text(QuotaUnit.displayAmount(quota.total, unit: quota.unit))
                .font(.caption.monospacedDigit())
                .foregroundStyle(.primary)
        }
    }

    private var usageRow: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 8) {
                Text(quota.label)
                    .frame(width: 58, alignment: .leading)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                QuotaProgressBar(fraction: quota.fraction, color: color(for: quota.fraction))
                Text(usageDetail)
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .frame(width: 56, alignment: .trailing)
            }
            if let resetText = quota.resetText, !resetText.isEmpty {
                Text(resetText)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .padding(.leading, 66)
            }
        }
    }

    private var usageDetail: String {
        if quota.unit == "%" { return String(format: "%.0f%% 已用", quota.fraction * 100) }
        return "\(compact(quota.used))/\(compact(quota.total))"
    }

    /// Windows with a non-percent unit print as raw counts. Clamped because a
    /// mis-parsed page can hand us a value far outside Int's range, and
    /// `Int(_: Double)` would trap on it.
    private func compact(_ value: Double) -> String {
        guard value.isFinite else { return "0" }
        return String(format: "%.0f", min(max(value, -1e15), 1e15))
    }

    private func color(for fraction: Double) -> Color {
        if fraction >= 0.95 { return .red }
        if fraction >= 0.80 { return .orange }
        return .blue
    }
}

private struct QuotaProgressBar: View {
    let fraction: Double
    let color: Color

    var body: some View {
        GeometryReader { proxy in
            let clamped = min(max(fraction, 0), 1)
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.secondary.opacity(0.18))
                Capsule()
                    .fill(color)
                    .frame(width: max(4, proxy.size.width * clamped))
            }
        }
        .frame(height: 6)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("用量")
        .accessibilityValue(String(format: "%.0f%%", fraction * 100))
    }
}
