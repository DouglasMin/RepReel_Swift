import Foundation

/// Build-time configuration, injected from `Config/*.xcconfig` into each target's
/// Info.plist. The app and the share extension both read their own `Bundle.main`,
/// and both get the same values because they share the xcconfig.
public struct AppConfig: Sendable {
    public let apiHost: String
    public let apiStagePath: String
    public let appSecret: String
    public let appGroupID: String
    /// Only used until Sign in with Apple lands; see `UserIdentityStore`.
    public let developmentUserEmail: String?

    public init(
        apiHost: String,
        apiStagePath: String = "",
        appSecret: String,
        appGroupID: String,
        developmentUserEmail: String? = nil
    ) {
        self.apiHost = apiHost
        self.apiStagePath = apiStagePath
        self.appSecret = appSecret
        self.appGroupID = appGroupID
        self.developmentUserEmail = developmentUserEmail
    }

    public var baseURL: URL {
        var components = URLComponents()
        components.scheme = "https"
        components.host = apiHost
        components.path = apiStagePath
        guard let url = components.url else {
            preconditionFailure("APIHost '\(apiHost)' is not a valid host")
        }
        return url
    }

    public enum ConfigError: Error, CustomStringConvertible {
        case missingKey(String)
        case placeholderValue(String)

        public var description: String {
            switch self {
            case .missingKey(let key):
                "Info.plist is missing '\(key)'. Check Config/Secrets.xcconfig."
            case .placeholderValue(let key):
                "Info.plist key '\(key)' still holds the example placeholder. " +
                "Copy Config/Secrets.example.xcconfig to Config/Secrets.xcconfig and fill it in."
            }
        }
    }

    public static func fromBundle(_ bundle: Bundle = .main) throws -> AppConfig {
        func string(_ key: String) throws -> String {
            guard let value = bundle.object(forInfoDictionaryKey: key) as? String,
                  !value.isEmpty else {
                throw ConfigError.missingKey(key)
            }
            guard !value.contains("REPLACE_ME") else {
                throw ConfigError.placeholderValue(key)
            }
            return value
        }

        let devEmail = bundle.object(forInfoDictionaryKey: "DevUserEmail") as? String

        return AppConfig(
            apiHost: try string("APIHost"),
            apiStagePath: (bundle.object(forInfoDictionaryKey: "APIStagePath") as? String) ?? "",
            appSecret: try string("AppSecret"),
            appGroupID: try string("AppGroupID"),
            developmentUserEmail: (devEmail?.isEmpty == false) ? devEmail : nil
        )
    }
}
