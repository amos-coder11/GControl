import SwiftUI

/// Fondo de Inicio: `HomeBackdrop` (`fondo1.png`), visible completo en pantalla.
struct DashboardHomeBackdropImage: View {
    var body: some View {
        GeometryReader { geo in
            ZStack {
                Color.black

                Image("HomeBackdrop")
                    .resizable()
                    .scaledToFit()
                    .frame(width: geo.size.width, height: geo.size.height)
                    .position(x: geo.size.width * 0.5, y: geo.size.height * 0.5)

                LinearGradient(
                    colors: [
                        Color.black.opacity(0.52),
                        Color.black.opacity(0.18),
                        Color.black.opacity(0.55),
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(width: geo.size.width, height: geo.size.height)
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
        .ignoresSafeArea(.all)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
