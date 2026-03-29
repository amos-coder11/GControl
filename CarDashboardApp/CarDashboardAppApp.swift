import SwiftUI

@main
struct CarDashboardAppApp: App {
    @StateObject private var carsVM = CarsViewModel()
    @StateObject private var settingsVM = SettingsViewModel()

    var body: some Scene {
        WindowGroup {
            MainTabView()
                .environmentObject(carsVM)
                .environmentObject(settingsVM)
                .preferredColorScheme(settingsVM.preferredColorScheme)
        }
    }
}
