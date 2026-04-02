import Foundation

/// Build/runtime environment for backend base URL selection.
enum AppEnvironment: String, CaseIterable, Identifiable {
    case dev
    case staging
    case prod

    var id: String { rawValue }
}
