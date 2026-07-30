import SwiftUI

enum TabItem: Int, CaseIterable, Identifiable {
    case home = 0
    case chat = 1
    case sessions = 2
    case settings = 3
    case account = 4

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .home: return "Home"
        case .chat: return "Chat"
        case .sessions: return "Sessions"
        case .settings: return "Tú"
        case .account: return "Account"
        }
    }

    var icon: String {
        switch self {
        case .home: return "house.fill"
        case .chat: return "ellipsis.bubble"
        case .sessions: return "doc.text"
        case .settings: return "person.crop.circle"
        case .account: return "person"
        }
    }

    var selectedIcon: String {
        switch self {
        case .home: return "house.fill"
        case .chat: return "ellipsis.bubble.fill"
        case .sessions: return "doc.text.fill"
        case .settings: return "person.crop.circle.fill"
        case .account: return "person.fill"
        }
    }
}

/// Barra flotante alineada con GROO (Home · Chat · Sessions · Tú · Account).
struct LiquidGlassTabBar: View {
    @Binding var selectedTab: TabItem
    var onAuxiliaryTap: () -> Void = {}

    var body: some View {
        HStack(spacing: 0) {
            ForEach(TabItem.allCases) { tab in
                let isSelected = selectedTab == tab
                Button {
                    selectedTab = tab
                } label: {
                    VStack(spacing: 4) {
                        Image(systemName: isSelected ? tab.selectedIcon : tab.icon)
                            .font(.system(size: 20, weight: isSelected ? .semibold : .regular))
                            .foregroundStyle(isSelected ? GrooBrand.purple : Color(red: 0.55, green: 0.55, blue: 0.58))
                        Text(tab.title)
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(isSelected ? GrooBrand.purple : Color(red: 0.55, green: 0.55, blue: 0.58))
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.top, 8)
        .padding(.bottom, 4)
        .background(Color.white)
    }
}

#Preview {
    LiquidGlassTabBar(selectedTab: .constant(.home))
}
