import Foundation

enum UpdateConfiguration {
    enum Failure: LocalizedError {
        case invalidFeed
        case invalidKey

        var errorDescription: String? {
            switch self {
            case .invalidFeed: return "This build needs a valid HTTPS update feed."
            case .invalidKey: return "This build needs a valid Sparkle public signing key."
            }
        }
    }

    static func validate(_ info: [String: Any]) throws {
        guard let value = info["SUFeedURL"] as? String, let url = URL(string: value),
              url.scheme == "https", let host = url.host, !host.isEmpty,
              url.user == nil, url.password == nil, url.fragment == nil else {
            throw Failure.invalidFeed
        }
        guard let value = info["SUPublicEDKey"] as? String,
              let key = Data(base64Encoded: value), key.count == 32 else {
            throw Failure.invalidKey
        }
    }
}
