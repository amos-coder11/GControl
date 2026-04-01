import Combine
import SwiftUI
import UIKit

// MARK: - Enrutador de pestañas (mismo módulo que `CarsView` / `DashboardView`)

enum CarHubMainTab: Hashable {
    case home
    case cars
    case chat
    case settings
    case search
}

@MainActor
final class MainTabRouter: ObservableObject {
    @Published var selected: CarHubMainTab = .home
}

// MARK: - Pestañas (TabView nativo iOS 26 + Liquid Glass del sistema)

struct MainTabView: View {
    @StateObject private var tabRouter = MainTabRouter()
    @StateObject private var invoiceHistory = InvoiceHistoryStore()
    @StateObject private var notificationsStore = DashboardNotificationsStore()
    @StateObject private var chatInbox = ChatInboxStore()
    @State private var chatSearchText = ""

    @EnvironmentObject var carsVM: CarsViewModel

    var body: some View {
        TabView(selection: $tabRouter.selected) {
            Tab("Inicio", systemImage: "house.fill", value: CarHubMainTab.home) {
                NavigationStack {
                    DashboardView()
                }
            }

            Tab("Coches", systemImage: "car.fill", value: CarHubMainTab.cars) {
                NavigationStack {
                    CarsView()
                }
            }

            Tab("Chat", systemImage: "bubble.left.and.bubble.right.fill", value: CarHubMainTab.chat) {
                ChatView(searchText: $chatSearchText)
            }
            .badge(chatInbox.totalUnansweredMessageCount)

            Tab("Ajustes", systemImage: "gearshape.fill", value: CarHubMainTab.settings) {
                NavigationStack {
                    SettingsView()
                }
            }

            Tab("Buscador", systemImage: "magnifyingglass", value: CarHubMainTab.search) {
                SearchView()
                    .environmentObject(carsVM)
            }
        }
        .environmentObject(chatInbox)
        .environmentObject(tabRouter)
        .environmentObject(invoiceHistory)
        .environmentObject(notificationsStore)
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
