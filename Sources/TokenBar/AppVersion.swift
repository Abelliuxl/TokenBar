import Foundation

public enum AppVersion {
    public static let marketing: String = {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.0.0"
    }()

    public static let build: String = {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "0"
    }()

    public static var display: String {
        "v\(marketing) (\(build))"
    }
}
