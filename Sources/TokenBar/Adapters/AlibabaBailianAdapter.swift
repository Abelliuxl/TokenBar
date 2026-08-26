import Foundation

/// Adapter for 阿里百炼 (Alibaba Cloud Model Studio).
///
/// Uses the Alibaba Cloud BSS QueryAccountBalance OpenAPI with a RAM
/// AccessKey pair. There is intentionally no web-session or OAuth mode.
public struct AlibabaBailianAdapter: MultiModeProviderAdapter {
    public let id = "bailian"
    public var displayName: String { "阿里百炼" }
    public var iconSystemName: String { "sparkles" }
    public var brandIcon: BrandIcon? { .bailian }
    public var supportsWebLogin: Bool { false }
    public var loginURL: URL { URL(string: "https://business.aliyuncs.com/")! }

    public let defaultFetchModeId = "accessKey"
    public let fetchModes = [
        ProviderFetchMode(
            id: "accessKey",
            title: "AccessKey 凭证",
            credentialFields: [
                ProviderCredentialField(
                    id: "accessKeyId",
                    title: "AccessKey ID",
                    placeholder: "LTAI..."
                ),
                ProviderCredentialField(
                    id: "accessKeySecret",
                    title: "AccessKey Secret",
                    placeholder: "仅保存在本机 TokenBar 配置",
                    isSecret: true
                ),
            ]
        ),
    ]

    public func fetch() async -> Snapshot {
        let modeId = defaultFetchModeId
        guard let accessKeyId = ProviderCredentialStore.value(providerId: id, modeId: modeId, fieldId: "accessKeyId"),
              let accessKeySecret = ProviderCredentialStore.value(providerId: id, modeId: modeId, fieldId: "accessKeySecret"),
              !accessKeyId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !accessKeySecret.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return Snapshot(providerId: id, quotas: [], status: .error("请在“访问方式 → AccessKey 凭证”中配置 AccessKey ID 和 Secret"))
        }

        return await AlibabaCloudBSSOpenAPI.fetchBalance(
            providerId: id,
            accessKeyId: accessKeyId.trimmingCharacters(in: .whitespacesAndNewlines),
            accessKeySecret: accessKeySecret.trimmingCharacters(in: .whitespacesAndNewlines)
        )
    }
}
