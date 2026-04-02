import Foundation

/// Loads per-environment backend base URLs from `Config.plist` (bundled, no secrets).
enum AppConfig {
    private enum PlistKeys {
        static let dev = "baseURL_dev"
        static let staging = "baseURL_staging"
        static let prod = "baseURL_prod"
    }

    private static let userDefaultsOverrideKey = "VoiceApp.customBackendBaseURL"

    /// Returns the configured backend root URL for the given environment (trailing slash stripped).
    static func baseURL(for environment: AppEnvironment) throws -> URL {
        guard let url = Bundle.main.url(forResource: "Config", withExtension: "plist") else {
            throw AppError.webRTCConnectionFailed(reason: "Missing Config.plist in bundle.")
        }
        let data = try Data(contentsOf: url)
        let plist = try PropertyListSerialization.propertyList(from: data, format: nil)
        guard let dict = plist as? [String: String] else {
            throw AppError.webRTCConnectionFailed(reason: "Invalid Config.plist structure.")
        }

        let key: String
        switch environment {
        case .dev: key = PlistKeys.dev
        case .staging: key = PlistKeys.staging
        case .prod: key = PlistKeys.prod
        }

        guard let raw = dict[key], let url = URL(string: raw) else {
            throw AppError.webRTCConnectionFailed(reason: "Missing or invalid URL for \(environment.rawValue).")
        }
        return normalize(url)
    }

    /// Applies optional user override from `UserDefaults` (settings sheet).
    static func resolvedBaseURL(environment: AppEnvironment) throws -> URL {
        if let override = UserDefaults.standard.string(forKey: userDefaultsOverrideKey),
           let u = URL(string: override), !override.isEmpty {
            return normalize(u)
        }
        return try baseURL(for: environment)
    }

    /// Persists backend base URL override (empty string clears override).
    static func setCustomBackendBaseURL(_ string: String) {
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            UserDefaults.standard.removeObject(forKey: userDefaultsOverrideKey)
        } else {
            UserDefaults.standard.set(trimmed, forKey: userDefaultsOverrideKey)
        }
    }

    private static func normalize(_ url: URL) -> URL {
        guard var c = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return url }
        if c.path.hasSuffix("/") {
            c.path = String(c.path.dropLast())
        }
        return c.url ?? url
    }
}
