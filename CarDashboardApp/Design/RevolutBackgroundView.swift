import SwiftUI

/// Fondo blanco unificado (misma base que el header).
struct RevolutBackgroundView: View {
    var body: some View {
        Color.white
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
