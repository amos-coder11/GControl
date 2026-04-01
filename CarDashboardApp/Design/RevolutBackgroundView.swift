import SwiftUI

/// Fondo estilo Revolut: negro profundo con **un haz de luz** frío (mesh 4×4), movimiento muy lento.
/// No usa múltiples blobs difusos; el brillo queda concentrado en una zona (~≤30 % perceptiva).
struct RevolutBackgroundView: View {
    private let startDate = Date()

    private static let voidBlack = Color(red: 5 / 255, green: 5 / 255, blue: 9 / 255) // más profundo que antes
    /// #B8D4E8 — reflejo blanquecino-azulado
    private static let iceHighlight = Color(red: 184 / 255, green: 212 / 255, blue: 232 / 255)
    /// #6BA4CC — azul hielo
    private static let iceCore = Color(red: 107 / 255, green: 164 / 255, blue: 204 / 255)

    var body: some View {
        ZStack {
            Color.black

            TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: false)) { timeline in
                let t = Float(timeline.date.timeIntervalSince(startDate))
                // Movimiento muy lento (equivalente a speed ~0.15–0.2 del prompt)
                let u = t * 0.16

                let p00 = SIMD2<Float>(0, 0)
                let p01 = SIMD2<Float>(0.33, 0)
                let p02 = SIMD2<Float>(0.67, 0)
                let p03 = SIMD2<Float>(1, 0)

                let p10 = SIMD2<Float>(0, 0.33)
                let p11 = SIMD2<Float>(
                    0.34 + 0.07 * sin(u * 0.13),
                    0.29 + 0.045 * cos(u * 0.1)
                )
                let p12 = SIMD2<Float>(
                    0.57 + 0.055 * cos(u * 0.11),
                    0.31 + 0.038 * sin(u * 0.12)
                )
                let p13 = SIMD2<Float>(1, 0.33)

                let p20 = SIMD2<Float>(0, 0.66)
                let p21 = SIMD2<Float>(
                    0.31 + 0.04 * cos(u * 0.09),
                    0.61 + 0.028 * sin(u * 0.11)
                )
                let p22 = SIMD2<Float>(
                    0.6 + 0.04 * sin(u * 0.085),
                    0.63 + 0.032 * cos(u * 0.095)
                )
                let p23 = SIMD2<Float>(1, 0.66)

                let p30 = SIMD2<Float>(0, 1)
                let p31 = SIMD2<Float>(0.33, 1)
                let p32 = SIMD2<Float>(0.67, 1)
                let p33 = SIMD2<Float>(1, 1)

                let points: [SIMD2<Float>] = [
                    p00, p01, p02, p03,
                    p10, p11, p12, p13,
                    p20, p21, p22, p23,
                    p30, p31, p32, p33,
                ]

                let pulse = 0.38 + 0.08 * sin(Double(t) * 0.2)
                let rim = 0.12 + 0.04 * sin(Double(t) * 0.17)

                let cIceHi = Self.iceHighlight.opacity(pulse * 0.26)
                let cIceCore = Self.iceCore.opacity(pulse * 0.32)
                let cDeep = Color(red: 0.04, green: 0.07, blue: 0.12).opacity(rim)
                let cTail = Color(red: 0.035, green: 0.065, blue: 0.1).opacity(rim * 0.5)
                let cBlack = Color.black
                let cVoid = Self.voidBlack

                let colors: [Color] = [
                    cBlack, cBlack, cBlack, cBlack,
                    cBlack, cDeep, cIceCore, cBlack,
                    cBlack, cTail, cIceHi, cBlack,
                    cVoid, cVoid, cVoid, cVoid,
                ]

                MeshGradient(
                    width: 4,
                    height: 4,
                    points: points,
                    colors: colors,
                    smoothsColors: true
                )
            }

            // Viñeta suave: refuerza negro en bordes (haz más “concentrado”)
            LinearGradient(
                stops: [
                    .init(color: .black.opacity(0.68), location: 0),
                    .init(color: .clear, location: 0.2),
                    .init(color: .clear, location: 0.8),
                    .init(color: .black.opacity(0.64), location: 1),
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .allowsHitTesting(false)

            LinearGradient(
                stops: [
                    .init(color: .black.opacity(0.48), location: 0),
                    .init(color: .clear, location: 0.18),
                    .init(color: .clear, location: 0.82),
                    .init(color: .black.opacity(0.44), location: 1),
                ],
                startPoint: .leading,
                endPoint: .trailing
            )
            .allowsHitTesting(false)
        }
        .ignoresSafeArea()
    }
}

/// Mismo fondo animado que Inicio + modo oscuro (Chat, Coches, Ajustes, Buscador).
struct RevolutChromeContainer<Content: View>: View {
    @ViewBuilder var content: () -> Content

    var body: some View {
        ZStack {
            RevolutBackgroundView()
            content()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        // Tema claro en Ajustes no debe “romper” colores semánticos aquí: forzamos oscuro en todo el subárbol.
        .environment(\.colorScheme, .dark)
        .preferredColorScheme(.dark)
    }
}

#Preview {
    RevolutBackgroundView()
}
