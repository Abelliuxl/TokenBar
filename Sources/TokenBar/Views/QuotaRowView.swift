import SwiftUI

public struct QuotaRowView: View {
    let quota: Quota
    public init(quota: Quota) { self.quota = quota }

    public var body: some View {
        HStack(spacing: 8) {
            Text(quota.label)
                .frame(width: 40, alignment: .leading)
                .font(.caption)
                .foregroundStyle(.secondary)
            ProgressView(value: quota.fraction)
                .progressViewStyle(.linear)
                .tint(color(for: quota.fraction))
            Text(detail)
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: 64, alignment: .trailing)
        }
        .padding(.vertical, 2)
    }

    private var detail: String {
        if quota.unit == "%" { return String(format: "%.0f%% used", quota.fraction * 100) }
        if quota.unit == "¥" { return "¥\(String(format: "%.2f", quota.total))" }
        return "\(Int(quota.used))/\(Int(quota.total))"
    }

    private func color(for fraction: Double) -> Color {
        if fraction >= 0.95 { return .red }
        if fraction >= 0.80 { return .orange }
        return .accentColor
    }
}
