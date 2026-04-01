import SwiftUI
import UIKit

// MARK: - Pestañas (TabView nativo iOS 26 + Liquid Glass del sistema)

private enum MainAppTab: Hashable {
    case home, cars, chat, settings, search
}

struct MainTabView: View {
    @State private var selectedTab: MainAppTab = .home
    @State private var chatSearchText = ""

    @StateObject private var chatInbox = ChatInboxStore()
    @EnvironmentObject var carsVM: CarsViewModel

    var body: some View {
        TabView(selection: $selectedTab) {
            Tab("Inicio", systemImage: "house.fill", value: MainAppTab.home) {
                NavigationStack {
                    DashboardView()
                }
            }

            Tab("Coches", systemImage: "car.fill", value: MainAppTab.cars) {
                NavigationStack {
                    CarsView()
                }
            }

            Tab("Chat", systemImage: "bubble.left.and.bubble.right.fill", value: MainAppTab.chat) {
                ChatView(searchText: $chatSearchText)
            }
            .badge(chatInbox.totalUnansweredMessageCount)

            Tab("Ajustes", systemImage: "gearshape.fill", value: MainAppTab.settings) {
                NavigationStack {
                    SettingsView()
                }
            }

            Tab("Buscador", systemImage: "magnifyingglass", value: MainAppTab.search) {
                SearchView()
                    .environmentObject(carsVM)
            }
        }
        .environmentObject(chatInbox)
        /// Anula el `AccentColor` azul del catálogo: la tab seleccionada debe ser blanca, no azul.
        .accentColor(.white)
        .tint(.white)
        .onAppear {
            MainTabBarAppearance.applyWhiteSelection()
        }
        .toolbarBackground(PremiumAccent.tabBarDockBackgroundGradient, for: .tabBar)
        .toolbarBackground(.visible, for: .tabBar)
        .toolbarColorScheme(.dark, for: .tabBar)
        .tabBarMinimizeBehavior(.onScrollDown)
        .task {
            await carsVM.loadVehicles()
        }
    }
}

// MARK: - UITabBar (icono + título blancos al seleccionar; sin tinte azul del acento global)

private enum MainTabBarAppearance {
    static func applyWhiteSelection() {
        let normal = UIColor.white.withAlphaComponent(0.56)
        let selected = UIColor.white

        let item = UITabBarItemAppearance()
        item.normal.iconColor = normal
        item.normal.titleTextAttributes = [.foregroundColor: normal]
        item.selected.iconColor = selected
        item.selected.titleTextAttributes = [.foregroundColor: selected]

        let appearance = UITabBarAppearance()
        appearance.configureWithTransparentBackground()
        appearance.shadowImage = UIImage()
        appearance.shadowColor = .clear

        appearance.stackedLayoutAppearance = item
        appearance.inlineLayoutAppearance = item
        appearance.compactInlineLayoutAppearance = item

        let bar = UITabBar.appearance()
        bar.standardAppearance = appearance
        bar.scrollEdgeAppearance = appearance
        bar.isTranslucent = true
        bar.tintColor = selected
        bar.unselectedItemTintColor = normal
        bar.barTintColor = nil
        bar.backgroundColor = .clear
    }
}

#Preview {
    MainTabView()
        .environmentObject(CarsViewModel())
        .environmentObject(SettingsViewModel())
        .environmentObject(AuthViewModel())
}
