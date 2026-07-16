import SwiftUI

/// Fondo blanco con orbe / difuminado morado en la esquina superior derecha.
struct RevolutBackgroundView: View {
    var body: some View {
        ZStack {
            Color.white

            // Halo suave que se funde con el fondo
            RadialGradient(
                colors: [
                    GrooBrand.purple.opacity(0.28),
                    GrooBrand.purple.opacity(0.12),
                    GrooBrand.purple.opacity(0.03),
                    Color.clear
                ],
                center: UnitPoint(x: 0.92, y: 0.02),
                startRadius: 20,
                endRadius: 380
            )
            .blur(radius: 8)
            .allowsHitTesting(false)

            // Orbe de cristal (más definido, como el mock)
            Circle()
                .fill(
                    RadialGradient(
                        colors: [
                            Color.white.opacity(0.55),
                            GrooBrand.purple.opacity(0.45),
                            GrooBrand.purple.opacity(0.22),
                            Color.clear
                        ],
                        center: UnitPoint(x: 0.35, y: 0.28),
                        startRadius: 2,
                        endRadius: 110
                    )
                )
                .frame(width: 200, height: 200)
                .blur(radius: 18)
                .offset(x: 78, y: -70)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                .allowsHitTesting(false)
        }
        .ignoresSafeArea()
    }
}

/// Contenedor principal con fondo blanco y tema claro.
struct RevolutChromeContainer<Content: View>: View {
    @ViewBuilder var content: () -> Content

    var body: some View {
        ZStack {
            RevolutBackgroundView()
            content()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .environment(\.colorScheme, .light)
        .preferredColorScheme(.light)
    }
}

#Preview {
    RevolutBackgroundView()
}
