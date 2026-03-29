import Foundation
import SwiftUI

@MainActor
final class SettingsViewModel: ObservableObject {
    @Published var userName: String = "Carlos"
    @Published var useMph: Bool = false
    @Published var animationsEnabled: Bool = true
    @Published var simulatedData: Bool = true
    @Published var leadsNotificationsEnabled: Bool = true
    @Published var leadsFollowUpReminders: Bool = true
    /// Default: light so the dashboard matches a white background out of the box.
    @Published var theme: AppTheme = .light

    let appVersion = "1.0.0"
    let buildNumber = "2025.03"

    enum AppTheme: String, CaseIterable, Identifiable {
        case light = "Claro"
        case dark = "Oscuro"
        case system = "Sistema"

        var id: String { rawValue }
    }

    /// Drives `WindowGroup` appearance; `nil` follows system when theme is `.system`.
    var preferredColorScheme: ColorScheme? {
        switch theme {
        case .light: return .light
        case .dark: return .dark
        case .system: return nil
        }
    }

    var speedUnit: String {
        useMph ? "mph" : "km/h"
    }
}
