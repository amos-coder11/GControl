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

    /// Fondo del dock de pestañas (#0501FF → #4D01FF).
    static let tabBarDockBackgroundGradient = LinearGradient(
        colors: [
            Color(red: 5 / 255, green: 1 / 255, blue: 255 / 255),
            Color(red: 77 / 255, green: 1 / 255, blue: 255 / 255)
        ],
        startPoint: .top,
        endPoint: .bottom
    )
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

// MARK: - Cabecera Inicio = Coches / Buscador (material oscuro + bisel, sin velo claro extra)

/// Píldora de búsqueda igual que `DashboardHomeTopBar`.
struct DashboardChromeSearchCapsuleBackground: View {
    var body: some View {
        Capsule(style: .continuous)
            .fill(.ultraThinMaterial)
            .environment(\.colorScheme, .dark)
            .overlay {
                Capsule(style: .continuous)
                    .strokeBorder(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(0.38),
                                Color.white.opacity(0.1),
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 0.65
                    )
            }
    }
}

/// Tarjeta con el **mismo** cristal oscuro y bisel que la pastilla del buscador (Ajustes y similares).
struct DashboardChromeCardBackground: View {
    var cornerRadius: CGFloat

    var body: some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(.ultraThinMaterial)
            .environment(\.colorScheme, .dark)
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(0.38),
                                Color.white.opacity(0.1),
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 0.65
                    )
            }
    }
}

/// Contenedor de ajustes: mismo lenguaje visual que el buscador de cabecera.
struct ChromeSettingsCard<Content: View>: View {
    var cornerRadius: CGFloat
    var padding: CGFloat
    @ViewBuilder var content: () -> Content

    init(
        cornerRadius: CGFloat = 22,
        padding: CGFloat = 16,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.cornerRadius = cornerRadius
        self.padding = padding
        self.content = content
    }

    var body: some View {
        content()
            .padding(padding)
            .background {
                DashboardChromeCardBackground(cornerRadius: cornerRadius)
            }
    }
}

/// Botón circular de cabecera (estadísticas, notificaciones, ordenar, filtros…).
struct DashboardChromeHeaderCircleBackground: View {
    var size: CGFloat = 44

    var body: some View {
        Circle()
            .fill(.ultraThinMaterial)
            .environment(\.colorScheme, .dark)
            .frame(width: size, height: size)
            .overlay {
                Circle()
                    .strokeBorder(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(0.35),
                                Color.white.opacity(0.08),
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 0.65
                    )
            }
            .shadow(color: .black.opacity(0.35), radius: 10, x: 0, y: 4)
    }
}

/// Retroalimentación al pulsar: destello blanco (evita el resaltado azul del sistema en botones circulares).
struct ChromeCirclePressButtonStyle: ButtonStyle {
    /// Por defecto coincide con `AppChromeHeaderMetrics.circleButtonSize`.
    var diameter: CGFloat = 44

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .overlay {
                Circle()
                    .fill(Color.white.opacity(configuration.isPressed ? 0.28 : 0))
                    .frame(width: diameter, height: diameter)
            }
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

/// Misma idea para filas anchas (lista de chats).
struct ChromeRowPressButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(Color.white.opacity(configuration.isPressed ? 0.12 : 0))
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

/// Círculo pequeño (p. ej. enviar en el compositor).
struct ChromeSmallCirclePressButtonStyle: ButtonStyle {
    var diameter: CGFloat = 28

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .overlay {
                Circle()
                    .fill(Color.white.opacity(configuration.isPressed ? 0.35 : 0))
                    .frame(width: diameter, height: diameter)
            }
            .animation(.easeOut(duration: 0.1), value: configuration.isPressed)
    }
}

/// Colores del campo de búsqueda de Inicio (reutilizar en Coches/Buscador).
enum DashboardChromeSearchFieldStyle {
    static let iconOpacity: Double = 0.92
    static let promptOpacity: Double = 0.48
    static let iconClearOpacity: Double = 0.48
}

/// Misma posición y anchura del buscador que en Inicio (avatar + pastilla flexible + 2 círculos).
enum AppChromeHeaderMetrics {
    static let horizontalPadding: CGFloat = 16
    static let topPadding: CGFloat = 8
    static let bottomPadding: CGFloat = 12
    static let hStackSpacing: CGFloat = 10
    static let avatarSize: CGFloat = 48
    static let circleButtonSize: CGFloat = 44
}

extension View {
    /// Padding exterior de la fila cabecera (Inicio, Coches, Chat, Ajustes, Buscador).
    func appChromeHeaderOuterPadding() -> some View {
        padding(.horizontal, AppChromeHeaderMetrics.horizontalPadding)
            .padding(.top, AppChromeHeaderMetrics.topPadding)
            .padding(.bottom, AppChromeHeaderMetrics.bottomPadding)
    }
}

// MARK: - Buscador Coches (píldora + botones circulares)

private let liquidGlassFill = LinearGradient(
    colors: [
        Color.white.opacity(0.78),
        Color.white.opacity(0.28),
        Color.white.opacity(0.08),
    ],
    startPoint: .topLeading,
    endPoint: .bottomTrailing
)

private let liquidGlassStroke = LinearGradient(
    colors: [
        Color.white.opacity(0.95),
        Color.white.opacity(0.4),
        Color.gray.opacity(0.14),
    ],
    startPoint: .topLeading,
    endPoint: .bottomTrailing
)

/// Campo de búsqueda tipo pastilla (referencia Liquid Glass).
struct LiquidGlassSearchPillBackground: View {
    var body: some View {
        Capsule(style: .continuous)
            .fill(.ultraThinMaterial)
            .background {
                Capsule(style: .continuous)
                    .fill(liquidGlassFill)
            }
            .overlay {
                Capsule(style: .continuous)
                    .strokeBorder(liquidGlassStroke, lineWidth: 0.75)
            }
            .shadow(color: .black.opacity(0.06), radius: 14, x: 0, y: 6)
            .shadow(color: .black.opacity(0.03), radius: 2, x: 0, y: 1)
    }
}

/// Degradado suave para campos sobre fondo oscuro (evita el velo blanco demasiado fuerte de `liquidGlassFill`).
private let liquidGlassFormFieldOnDarkFill = LinearGradient(
    colors: [
        Color.white.opacity(0.38),
        Color.white.opacity(0.14),
        Color.white.opacity(0.05),
    ],
    startPoint: .topLeading,
    endPoint: .bottomTrailing
)

private let liquidGlassFormFieldOnDarkStroke = LinearGradient(
    colors: [
        Color.white.opacity(0.88),
        Color.white.opacity(0.38),
        Color.white.opacity(0.1),
    ],
    startPoint: .topLeading,
    endPoint: .bottomTrailing
)

/// Campo de formulario en hoja oscura: cristal más legible, brillo superior y bisel definido.
struct LiquidGlassFormFieldBackground: View {
    var cornerRadius: CGFloat = 16

    var body: some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(.thinMaterial)
            .environment(\.colorScheme, .dark)
            .background {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(liquidGlassFormFieldOnDarkFill)
            }
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(
                        LinearGradient(
                            stops: [
                                .init(color: Color.white.opacity(0.3), location: 0),
                                .init(color: Color.white.opacity(0.08), location: 0.2),
                                .init(color: Color.clear, location: 0.55),
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .allowsHitTesting(false)
            }
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(liquidGlassFormFieldOnDarkStroke, lineWidth: 0.7)
            }
            .shadow(color: .black.opacity(0.55), radius: 10, x: 0, y: 4)
            .shadow(color: .white.opacity(0.06), radius: 1, x: 0, y: -0.5)
    }
}

/// Agrupa campos en formularios modales oscuros: contenedor más suave para que resalten los inputs.
struct LiquidGlassDarkFormPanel<Content: View>: View {
    var cornerRadius: CGFloat = 20
    @ViewBuilder var content: () -> Content

    var body: some View {
        content()
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(.ultraThinMaterial)
                    .environment(\.colorScheme, .dark)
                    .background {
                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                            .fill(
                                LinearGradient(
                                    colors: [
                                        Color.white.opacity(0.09),
                                        Color.white.opacity(0.035),
                                        Color.white.opacity(0.015),
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
                                        Color.white.opacity(0.38),
                                        Color.white.opacity(0.14),
                                        Color.white.opacity(0.06),
                                    ],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ),
                                lineWidth: 0.65
                            )
                    }
                    .shadow(color: .black.opacity(0.28), radius: 18, x: 0, y: 10)
                    .shadow(color: .black.opacity(0.1), radius: 2, x: 0, y: 1)
            }
    }
}

private let keyboardAccessoryShape = UnevenRoundedRectangle(
    cornerRadii: RectangleCornerRadii(
        topLeading: 14,
        bottomLeading: 0,
        bottomTrailing: 0,
        topTrailing: 14
    ),
    style: .continuous
)

/// Franja encima del teclado (accesorio del sistema): mismo lenguaje visual que la pastilla de búsqueda, sin borde inferior.
struct LiquidGlassKeyboardAccessoryBar: View {
    var onDismiss: () -> Void

    var body: some View {
        ZStack(alignment: .trailing) {
            keyboardAccessoryShape
                .fill(.ultraThinMaterial)
                .background {
                    keyboardAccessoryShape
                        .fill(liquidGlassFill)
                }
                .overlay {
                    keyboardAccessoryShape
                        .strokeBorder(
                            LinearGradient(
                                colors: [
                                    Color.white.opacity(0.88),
                                    Color.white.opacity(0.38),
                                    Color.white.opacity(0.06),
                                ],
                                startPoint: .top,
                                endPoint: .bottom
                            ),
                            lineWidth: 0.65
                        )
                }
                .shadow(color: .black.opacity(0.04), radius: 8, x: 0, y: 4)

            Button {
                onDismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.95))
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(.trailing, 4)
            .accessibilityLabel("Cerrar teclado")
        }
        .frame(maxWidth: .infinity)
        .frame(height: 48)
    }
}

/// Degradado + bisel alineados con `LiquidGlassTabBar.floatingGlassCapsule` (misma lectura que las pestañas del sistema).
private let tabMatchedGlassFill = LinearGradient(
    colors: [
        Color.white.opacity(0.62),
        Color.white.opacity(0.18),
        Color.white.opacity(0.05),
    ],
    startPoint: .topLeading,
    endPoint: .bottomTrailing
)

private let tabMatchedGlassStroke = LinearGradient(
    colors: [
        Color.white.opacity(0.95),
        Color.white.opacity(0.3),
        Color.gray.opacity(0.12),
    ],
    startPoint: .topLeading,
    endPoint: .bottomTrailing
)

/// Botón circular: mismo lenguaje que la cápsula glass de la barra de pestañas (brillo superior, bisel y sombras más profundas).
struct LiquidGlassCircleButtonBackground: View {
    var body: some View {
        Circle()
            .fill(.ultraThinMaterial)
            .environment(\.colorScheme, .dark)
            .background {
                Circle()
                    .fill(tabMatchedGlassFill)
            }
            .overlay {
                // Reflejo tipo «lente» en la parte superior (acerca el aspecto al liquid glass del tab bar).
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [
                                Color.white.opacity(0.38),
                                Color.white.opacity(0.12),
                                Color.clear,
                            ],
                            center: UnitPoint(x: 0.38, y: 0.28),
                            startRadius: 1,
                            endRadius: 32
                        )
                    )
                    .allowsHitTesting(false)
            }
            .overlay {
                Circle()
                    .strokeBorder(tabMatchedGlassStroke, lineWidth: 0.75)
            }
            .shadow(color: .black.opacity(0.08), radius: 24, x: 0, y: 12)
            .shadow(color: .black.opacity(0.04), radius: 4, x: 0, y: 2)
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
