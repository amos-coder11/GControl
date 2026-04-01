import SwiftUI

enum TabItem: Int, CaseIterable, Identifiable {
    case home = 0
    case cars = 1
    case chat = 2
    case settings = 3

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .home: return "Inicio"
        case .cars: return "Coches"
        case .chat: return "Chat"
        case .settings: return "Ajustes"
        }
    }

    var icon: String {
        switch self {
        case .home: return "house.fill"
        case .cars: return "car.fill"
        case .chat: return "bubble.left.and.bubble.right.fill"
        case .settings: return "gearshape.fill"
        }
    }
}

/// Barra flotante estilo referencia: **cápsula glass** con tabs (icono + título) y **botón circular** aparte.
struct LiquidGlassTabBar: View {
    @Binding var selectedTab: TabItem
    /// Botón redondo: **Buscador** (sheet u otra acción).
    var onAuxiliaryTap: () -> Void = {}

    @Namespace private var tabNamespace

    private let selectionDiameter: CGFloat = 50
    private let auxiliarySize: CGFloat = 54

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            mainCapsule

            auxiliaryCircleButton
        }
        .padding(.horizontal, 20)
        .padding(.top, 6)
        .padding(.bottom, 12)
    }

    /// Cápsula principal: Inicio, Coches, Chat, Ajustes.
    private var mainCapsule: some View {
        HStack(spacing: 0) {
            ForEach(TabItem.allCases) { tab in
                tabPillButton(for: tab)
            }
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 8)
        .background {
            floatingGlassCapsule
        }
    }

    private var floatingGlassCapsule: some View {
        Capsule(style: .continuous)
            .fill(.ultraThinMaterial)
            .background {
                Capsule(style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(0.62),
                                Color.white.opacity(0.18),
                                Color.white.opacity(0.05)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            }
            .overlay {
                Capsule(style: .continuous)
                    .strokeBorder(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(0.95),
                                Color.white.opacity(0.3),
                                Color.gray.opacity(0.12)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 0.75
                    )
            }
            .shadow(color: .black.opacity(0.08), radius: 24, x: 0, y: 12)
            .shadow(color: .black.opacity(0.04), radius: 4, x: 0, y: 2)
    }

    private var auxiliaryCircleButton: some View {
        Button {
            onAuxiliaryTap()
        } label: {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(PremiumAccent.ink.opacity(0.78))
                .frame(width: auxiliarySize, height: auxiliarySize)
                .background {
                    Circle()
                        .fill(.ultraThinMaterial)
                        .background {
                            Circle()
                                .fill(
                                    LinearGradient(
                                        colors: [
                                            Color.white.opacity(0.62),
                                            Color.white.opacity(0.16),
                                            Color.white.opacity(0.05)
                                        ],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )
                        }
                        .overlay {
                            Circle()
                                .strokeBorder(
                                    LinearGradient(
                                        colors: [
                                            Color.white.opacity(0.95),
                                            Color.white.opacity(0.3),
                                            Color.gray.opacity(0.12)
                                        ],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    ),
                                    lineWidth: 0.75
                                )
                        }
                        .shadow(color: .black.opacity(0.08), radius: 22, x: 0, y: 11)
                        .shadow(color: .black.opacity(0.04), radius: 3, x: 0, y: 1)
                }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Buscador")
    }

    private func tabPillButton(for tab: TabItem) -> some View {
        let isSelected = selectedTab == tab

        return Button {
            withAnimation(.spring(response: 0.42, dampingFraction: 0.76)) {
                selectedTab = tab
            }
        } label: {
            ZStack {
                if isSelected {
                    Circle()
                        .fill(.thinMaterial)
                        .background {
                            Circle()
                                .fill(
                                    LinearGradient(
                                        colors: [
                                            Color.white.opacity(0.92),
                                            PremiumAccent.ice.opacity(0.38),
                                            Color.white.opacity(0.35)
                                        ],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )
                        }
                        .overlay {
                            Circle()
                                .strokeBorder(
                                    LinearGradient(
                                        colors: [
                                            Color.white.opacity(0.98),
                                            Color.white.opacity(0.35)
                                        ],
                                        startPoint: .top,
                                        endPoint: .bottom
                                    ),
                                    lineWidth: 0.65
                                )
                        }
                        .shadow(color: .black.opacity(0.07), radius: 10, x: 0, y: 5)
                        .frame(width: selectionDiameter, height: selectionDiameter)
                        .matchedGeometryEffect(id: "activeTabHighlight", in: tabNamespace)
                }

                VStack(spacing: 3) {
                    Image(systemName: tab.icon)
                        .font(.system(size: 18, weight: isSelected ? .semibold : .medium))
                        .symbolEffect(.bounce, value: isSelected)

                    Text(tab.title)
                        .font(.system(size: 9, weight: .semibold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                }
                .foregroundStyle(isSelected ? Color.white : Color.white.opacity(0.52))
            }
            .frame(maxWidth: .infinity)
            .frame(height: selectionDiameter)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    ZStack {
        Color.white.ignoresSafeArea()
        VStack {
            Spacer()
            LiquidGlassTabBar(selectedTab: .constant(.home))
        }
    }
}
