import SwiftUI

@main
struct CarDashboardAppApp: App {
    @StateObject private var authVM = AuthViewModel()
    @StateObject private var carsVM = CarsViewModel()
    @StateObject private var settingsVM = SettingsViewModel()

    var body: some Scene {
        WindowGroup {
            AuthRootView(auth: authVM)
                .environmentObject(carsVM)
                .environmentObject(settingsVM)
                .preferredColorScheme(settingsVM.preferredColorScheme)
        }
    }
}
