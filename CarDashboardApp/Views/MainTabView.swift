import SwiftUI

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
        .tabBarMinimizeBehavior(.onScrollDown)
        .task {
            await carsVM.loadVehicles()
        }
    }
}

#Preview {
    MainTabView()
        .environmentObject(CarsViewModel())
        .environmentObject(SettingsViewModel())
        .environmentObject(AuthViewModel())
}
