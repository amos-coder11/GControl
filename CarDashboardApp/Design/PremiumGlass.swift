import SwiftUI

/// Acentos suaves (coral, menta, hielo, ámbar) — solo iconos y highlights.
enum PremiumAccent {
    static let coral = Color(red: 0.96, green: 0.42, blue: 0.38)
    static let mint = Color(red: 0.42, green: 0.82, blue: 0.68)
    static let ice = Color(red: 0.52, green: 0.72, blue: 0.92)
    static let amber = Color(red: 0.96, green: 0.76, blue: 0.42)
    static let ink = Color(red: 0.18, green: 0.22, blue: 0.28)
    /// Azul de ítem activo en tab bar (estilo referencia tipo “Chats”).
    static let tabActive = Color(red: 0.16, green: 0.44, blue: 0.98)
}

/// Pastilla tipo glass para badges y chips (mini cápsula translúcida).
struct GlassCapsuleBadge: View {
    let text: String
    var isPositive: Bool = false

    var body: some View {
        Text(text)
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(isPositive ? PremiumAccent.mint : Color.primary.opacity(0.55))
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .background {
                Capsule(style: .continuous)
                    .fill(.ultraThinMaterial)
                    .overlay {
                        Capsule(style: .continuous)
                            .strokeBorder(
                                LinearGradient(
                                    colors: [
                                        Color.white.opacity(0.75),
                                        Color.white.opacity(0.2)
                                    ],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ),
                                lineWidth: 0.6
                            )
                    }
                    .shadow(color: .black.opacity(0.04), radius: 4, x: 0, y: 2)
            }
    }
}

/// Fondo Apple-style: material + velo blanco + borde luminoso superior (muy sutil).
struct LiquidGlassCardBackground: View {
    var cornerRadius: CGFloat

    var body: some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(.ultraThinMaterial)
            .background {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(0.72),
                                Color.white.opacity(0.22),
                                Color.white.opacity(0.06)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            }
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(0.95),
                                Color.white.opacity(0.35),
                                Color.gray.opacity(0.12)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 0.75
                    )
            }
            .shadow(color: .black.opacity(0.05), radius: 16, x: 0, y: 8)
            .shadow(color: .black.opacity(0.02), radius: 2, x: 0, y: 1)
    }
}

/// Badge glass sobre fotos oscuras (mini cápsula legible).
struct GlassPhotoBadge: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 10, weight: .bold))
            .foregroundStyle(.white.opacity(0.95))
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .background {
                Capsule(style: .continuous)
                    .fill(.ultraThinMaterial)
                    .environment(\.colorScheme, .dark)
                    .overlay {
                        Capsule(style: .continuous)
                            .strokeBorder(Color.white.opacity(0.35), lineWidth: 0.5)
                    }
            }
    }
}
