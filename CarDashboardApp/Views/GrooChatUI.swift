import SwiftUI

// MARK: - Theme

enum GrooChatTheme {
    static let header = Color(red: 0.10, green: 0.30, blue: 0.71)
    static let headerDeep = Color(red: 0.06, green: 0.20, blue: 0.52)

    static var headerGradient: LinearGradient {
        LinearGradient(
            colors: [header, headerDeep],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    /// Cabecera suave blanco → azul claro (inbox / scroll sticky).
    static let softHeaderLeft = Color.white
    static let softHeaderRight = Color(red: 0.80, green: 0.87, blue: 0.98)

    static var softHeaderGradient: LinearGradient {
        LinearGradient(
            colors: [softHeaderLeft, softHeaderRight],
            startPoint: .leading,
            endPoint: .trailing
        )
    }

    /// Fondo compacto del header activo (solo al hacer scroll).
    static var homeHeaderBackground: some View {
        ZStack {
            softHeaderGradient
            RadialGradient(
                colors: [
                    GrooBrand.primary.opacity(0.14),
                    GrooBrand.primary.opacity(0.04),
                    Color.clear
                ],
                center: UnitPoint(x: 0.94, y: 0.0),
                startRadius: 8,
                endRadius: 120
            )
        }
    }

    /// Lista estilo Telegram
    static let listBackground = Color(red: 0.97, green: 0.97, blue: 0.98)
    static let telegramBlue = Color(red: 0.20, green: 0.55, blue: 0.91)
    static let unreadBadge = Color(red: 0.20, green: 0.55, blue: 0.91)

    /// Wallpaper conversación (mint → sky)
    static let wallpaperTop = Color(red: 0.86, green: 0.94, blue: 0.97)
    static let wallpaperBottom = Color(red: 0.78, green: 0.90, blue: 0.97)

    /// Burbujas Telegram: salientes azul claro, entrantes blancas.
    static let outgoingBubble = Color(red: 0.82, green: 0.93, blue: 0.99)
    static let outgoingBubbleEdge = Color(red: 0.68, green: 0.84, blue: 0.95)
    static let incomingBubble = Color.white
    static let sendButton = telegramBlue
    static let outgoingText = Color(red: 0.05, green: 0.08, blue: 0.16)
    static let incomingText = Color(red: 0.05, green: 0.08, blue: 0.16)
    static let metaText = Color.black.opacity(0.32)
    static let outgoingMeta = Color(red: 0.40, green: 0.58, blue: 0.72)
    static let readChecks = Color(red: 0.35, green: 0.65, blue: 0.95)
    static let composerBar = Color.clear
    static let separator = Color.black.opacity(0.08)

    /// Pill flotante estilo Telegram / iOS
    static func glassPillBackground() -> some View {
        Capsule(style: .continuous)
            .fill(.ultraThinMaterial)
            .overlay {
                Capsule(style: .continuous)
                    .fill(Color.white.opacity(0.55))
            }
            .overlay {
                Capsule(style: .continuous)
                    .strokeBorder(Color.white.opacity(0.75), lineWidth: 0.5)
            }
            .shadow(color: .black.opacity(0.06), radius: 10, y: 3)
    }

    static func glassCircleBackground() -> some View {
        Circle()
            .fill(.ultraThinMaterial)
            .overlay(Circle().fill(Color.white.opacity(0.72)))
            .overlay(Circle().strokeBorder(Color.white.opacity(0.95), lineWidth: 0.8))
            .shadow(color: .black.opacity(0.08), radius: 8, y: 2)
    }

    /// Campo con texto: esquinas suaves si crece.
    static func composerFieldBackground(isExpanded: Bool) -> some View {
        let radius: CGFloat = isExpanded ? 20 : 22
        return RoundedRectangle(cornerRadius: radius, style: .continuous)
            .fill(.ultraThinMaterial)
            .overlay {
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .fill(Color.white.opacity(isExpanded ? 0.72 : 0.88))
            }
            .overlay {
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.95), lineWidth: isExpanded ? 0.6 : 1)
            }
            .shadow(color: .black.opacity(0.08), radius: 8, y: 2)
    }

    /// Difuminado Apple que se desvanece (no header sólido).
    static func floatingBlurChrome() -> some View {
        ZStack(alignment: .top) {
            Rectangle()
                .fill(.ultraThinMaterial)
            LinearGradient(
                colors: [
                    Color.white.opacity(0.18),
                    Color.white.opacity(0.05),
                    Color.clear
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        }
        .mask {
            LinearGradient(
                colors: [
                    Color.black,
                    Color.black.opacity(0.85),
                    Color.black.opacity(0.35),
                    Color.clear
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        }
        .allowsHitTesting(false)
    }

    /// Difuminado inferior (composer + chips) que se desvanece hacia arriba.
    static func floatingBlurChromeBottom() -> some View {
        ZStack(alignment: .bottom) {
            Rectangle()
                .fill(.ultraThinMaterial)
            LinearGradient(
                colors: [
                    Color.clear,
                    Color.white.opacity(0.08),
                    Color.white.opacity(0.22)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        }
        .mask {
            LinearGradient(
                colors: [
                    Color.clear,
                    Color.black.opacity(0.25),
                    Color.black.opacity(0.7),
                    Color.black.opacity(0.95),
                    Color.black
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        }
        .allowsHitTesting(false)
    }
}

// MARK: - Diseño clínico (UI profesional unificada)

enum GrooClinicDesign {
    static let screenBackground = DrflowTheme.background
    static let cardBackground = Color.white
    static let cardRadius: CGFloat = 16
    static let sectionSpacing: CGFloat = 20

    struct ScreenBackground: View {
        var body: some View {
            screenBackground.ignoresSafeArea()
        }
    }

    struct SectionHeader: View {
        let title: String
        var subtitle: String?
        var actionTitle: String?
        var action: (() -> Void)?

        var body: some View {
            HStack(alignment: .bottom) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(DrflowTheme.textTertiary)
                        .textCase(.uppercase)
                        .tracking(0.6)
                    if let subtitle {
                        Text(subtitle)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(DrflowTheme.textSecondary)
                    }
                }
                Spacer()
                if let actionTitle, let action {
                    Button(actionTitle, action: action)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(GrooBrand.primary)
                }
            }
        }
    }

    struct ProCard<Content: View>: View {
        @ViewBuilder var content: () -> Content

        var body: some View {
            content()
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background {
                    RoundedRectangle(cornerRadius: cardRadius, style: .continuous)
                        .fill(cardBackground)
                        .shadow(color: .black.opacity(0.04), radius: 10, y: 3)
                }
        }
    }

    struct KPIStrip: View {
        let items: [(label: String, value: String, icon: String)]

        var body: some View {
            HStack(spacing: 0) {
                ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                    if index > 0 {
                        Rectangle()
                            .fill(Color.black.opacity(0.06))
                            .frame(width: 1, height: 40)
                    }
                    VStack(spacing: 4) {
                        Image(systemName: item.icon)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(GrooBrand.primary)
                        Text(item.value)
                            .font(.system(size: 16, weight: .bold, design: .rounded))
                            .monospacedDigit()
                            .foregroundStyle(DrflowTheme.textPrimary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.75)
                        Text(item.label)
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(DrflowTheme.textTertiary)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            .padding(.vertical, 14)
            .background {
                RoundedRectangle(cornerRadius: cardRadius, style: .continuous)
                    .fill(cardBackground)
                    .shadow(color: .black.opacity(0.04), radius: 8, y: 2)
            }
        }
    }

    struct FilterChip: View {
        let title: String
        let isSelected: Bool
        let action: () -> Void

        var body: some View {
            Button(action: action) {
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(isSelected ? .white : DrflowTheme.textSecondary)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background {
                        Capsule().fill(isSelected ? GrooBrand.primary : Color.black.opacity(0.05))
                    }
            }
            .buttonStyle(.plain)
        }
    }

    struct QuickAction: View {
        let title: String
        let icon: String
        let action: () -> Void

        var body: some View {
            Button(action: action) {
                VStack(spacing: 6) {
                    Image(systemName: icon)
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(GrooBrand.primary)
                        .frame(width: 44, height: 44)
                        .background(Circle().fill(GrooBrand.primarySoft))
                    Text(title)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(DrflowTheme.textPrimary)
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                        .minimumScaleFactor(0.85)
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.plain)
        }
    }
}

// MARK: - Sticky soft header (solo degradado, sin fila de usuario)

/// Barra fija bajo la status bar — degradado blanco → azul claro.
struct GrooSoftStickyHeaderBar: View {
    var stripHeight: CGFloat = 12

    var body: some View {
        GrooChatTheme.softHeaderGradient
            .frame(maxWidth: .infinity)
            .frame(height: stripHeight)
            .background(alignment: .top) {
                GrooChatTheme.softHeaderGradient
                    .ignoresSafeArea(edges: .top)
            }
    }
}

/// Header con el mismo blanco del fondo de la app (status bar siempre + barra al scroll).
struct GrooActiveScrollHeader<Content: View>: View {
    var isVisible: Bool
    var backgroundColor: Color = DrflowTheme.background
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(spacing: 0) {
            if isVisible {
                content()
                    .padding(.horizontal, 16)
                    .padding(.top, 4)
                    .padding(.bottom, 12)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .frame(maxWidth: .infinity)
        .background {
            backgroundColor
                .ignoresSafeArea(edges: .top)
        }
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(Color.black.opacity(isVisible ? 0.04 : 0))
                .frame(height: 0.5)
        }
        .shadow(color: .black.opacity(isVisible ? 0.04 : 0), radius: 6, y: 2)
        .animation(.spring(response: 0.34, dampingFraction: 0.84), value: isVisible)
        .allowsHitTesting(isVisible)
        .accessibilityHidden(!isVisible)
        .zIndex(10)
    }
}

private struct GrooScrollYKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

extension View {
    /// Publica el desplazamiento vertical del scroll (positivo = hacia abajo).
    func grooTrackScrollY(_ binding: Binding<CGFloat>) -> some View {
        coordinateSpace(name: "grooScrollTrack")
            .onPreferenceChange(GrooScrollYKey.self) { binding.wrappedValue = $0 }
    }

    func grooScrollYReporter() -> some View {
        background {
            GeometryReader { proxy in
                Color.clear.preference(
                    key: GrooScrollYKey.self,
                    value: max(0, -proxy.frame(in: .named("grooScrollTrack")).minY)
                )
            }
        }
    }
}

// MARK: - Wallpaper

struct GrooChatWallpaper: View {
    var body: some View {
        GeometryReader { geo in
            let size = geo.size
            ZStack {
                Image("ChatBackdropBase")
                    .resizable()
                    .scaledToFill()
                    .frame(width: size.width, height: size.height)
                    .clipped()

                Image("ChatBackdropPattern")
                    .renderingMode(.template)
                    .resizable()
                    .scaledToFill()
                    .frame(width: size.width, height: size.height)
                    .clipped()
                    .foregroundStyle(Color.white.opacity(0.85))
                    .opacity(0.3)
                    .allowsHitTesting(false)
            }
        }
    }
}

// MARK: - Avatar

/// Paleta de avatares: dos rosas fuertes alternados por nombre.
enum GrooAvatarPalette {
    /// #FAC1FF
    static let softPink = Color(red: 250 / 255, green: 193 / 255, blue: 255 / 255)
    /// #FC97FF
    static let vividPink = Color(red: 252 / 255, green: 151 / 255, blue: 255 / 255)

    static let colors: [Color] = [softPink, vividPink]

    static func color(for seed: String) -> Color {
        let key = seed.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !key.isEmpty else { return colors[0] }
        let hash = key.unicodeScalars.reduce(into: 0) { partial, scalar in
            partial = partial &* 31 &+ Int(scalar.value)
        }
        return colors[abs(hash) % colors.count]
    }

    static func initial(from name: String) -> String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let first = trimmed.first else { return "?" }
        return String(first).uppercased()
    }
}

/// Avatar circular con la letra principal del nombre (colores variados).
struct GrooLetterAvatar: View {
    let name: String
    var size: CGFloat = 54
    var initialOverride: String? = nil

    private var letter: String {
        if let initialOverride {
            let t = initialOverride.trimmingCharacters(in: .whitespacesAndNewlines)
            if let ch = t.first { return String(ch).uppercased() }
        }
        return GrooAvatarPalette.initial(from: name)
    }

    private var fill: Color {
        GrooAvatarPalette.color(for: name)
    }

    var body: some View {
        Circle()
            .fill(fill)
            .frame(width: size, height: size)
            .overlay {
                Text(letter)
                    .font(.system(size: size * 0.42, weight: .bold, design: .rounded))
                    .foregroundStyle(Color(red: 0.55, green: 0.12, blue: 0.72))
            }
            .accessibilityLabel(name)
    }
}

struct GrooChatAvatar: View {
    var imageName: String = "GrooCharacter"
    var size: CGFloat = 52
    var showsOnlineRing: Bool = false
    var badge: String? = nil

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            Image(imageName)
                .resizable()
                .scaledToFill()
                .frame(width: size, height: size)
                .clipShape(Circle())
                .overlay {
                    Circle()
                        .strokeBorder(Color.white, lineWidth: 2)
                }
                .shadow(color: GrooBrand.primary.opacity(0.15), radius: 6, y: 2)

            if showsOnlineRing {
                Circle()
                    .fill(Color(red: 0.22, green: 0.84, blue: 0.48))
                    .frame(width: size * 0.26, height: size * 0.26)
                    .overlay(Circle().strokeBorder(Color.white, lineWidth: 2))
                    .offset(x: 2, y: 2)
            }

            if let badge, !badge.isEmpty {
                Text(badge)
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(GrooBrand.primary))
                    .offset(x: 4, y: 4)
            }
        }
    }
}

// MARK: - Inbox contact (clínica)

// MARK: - Bubble shape (Telegram: cola en la esquina inferior)

enum GrooMessageDeliveryStatus {
    case none, sent, delivered, read
}

struct GrooMessageBubbleShape: Shape {
    var isOutgoing: Bool
    var isLastInGroup: Bool

    func path(in rect: CGRect) -> Path {
        let r: CGFloat = 16
        let tail: CGFloat = isLastInGroup ? 4 : r
        var corners = RectangleCornerRadii(
            topLeading: r,
            bottomLeading: isOutgoing ? r : tail,
            bottomTrailing: isOutgoing ? tail : r,
            topTrailing: r
        )
        return UnevenRoundedRectangle(cornerRadii: corners, style: .continuous).path(in: rect)
    }
}

struct GrooChatImageLightboxItem: Identifiable {
    let id = UUID()
    let uiImage: UIImage?
    let remoteURL: URL?

    static func local(_ image: UIImage) -> GrooChatImageLightboxItem {
        GrooChatImageLightboxItem(uiImage: image, remoteURL: nil)
    }

    static func remote(_ url: URL) -> GrooChatImageLightboxItem {
        GrooChatImageLightboxItem(uiImage: nil, remoteURL: url)
    }
}

struct GrooChatImageLightbox: View {
    let item: GrooChatImageLightboxItem
    @Environment(\.dismiss) private var dismiss
    @State private var scale: CGFloat = 1
    @State private var lastScale: CGFloat = 1
    @State private var offset: CGSize = .zero
    @State private var lastOffset: CGSize = .zero
    @State private var loadedImage: UIImage?
    @State private var loadFailed = false

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
                .onTapGesture {
                    if scale <= 1.05 { dismiss() }
                }

            Group {
                if let image = item.uiImage ?? loadedImage {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                        .scaleEffect(scale)
                        .offset(offset)
                        .gesture(zoomGesture.simultaneously(with: panGesture))
                        .onTapGesture(count: 2) { toggleZoom() }
                } else if loadFailed {
                    VStack(spacing: 12) {
                        Image(systemName: "photo")
                            .font(.system(size: 40))
                            .foregroundStyle(.white.opacity(0.6))
                        Text("No se pudo cargar la imagen")
                            .font(.subheadline)
                            .foregroundStyle(.white.opacity(0.7))
                    }
                } else {
                    ProgressView()
                        .tint(.white)
                        .scaleEffect(1.2)
                }
            }
            .padding(.horizontal, 8)

            VStack {
                HStack {
                    Spacer()
                    Button { dismiss() } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 30))
                            .symbolRenderingMode(.palette)
                            .foregroundStyle(.white, Color.white.opacity(0.25))
                            .padding(16)
                    }
                    .accessibilityLabel("Cerrar")
                }
                Spacer()
            }
        }
        .task(id: item.id) {
            await loadRemoteImageIfNeeded()
        }
    }

    private var zoomGesture: some Gesture {
        MagnificationGesture()
            .onChanged { value in
                scale = min(max(lastScale * value, 1), 5)
            }
            .onEnded { _ in
                if scale <= 1.05 {
                    scale = 1
                    lastScale = 1
                    offset = .zero
                    lastOffset = .zero
                } else {
                    lastScale = scale
                }
            }
    }

    private var panGesture: some Gesture {
        DragGesture()
            .onChanged { value in
                guard scale > 1 else { return }
                offset = CGSize(
                    width: lastOffset.width + value.translation.width,
                    height: lastOffset.height + value.translation.height
                )
            }
            .onEnded { _ in
                lastOffset = offset
            }
    }

    private func toggleZoom() {
        withAnimation(.spring(response: 0.32, dampingFraction: 0.86)) {
            if scale > 1.05 {
                scale = 1
                lastScale = 1
                offset = .zero
                lastOffset = .zero
            } else {
                scale = 2.5
                lastScale = 2.5
            }
        }
    }

    @MainActor
    private func loadRemoteImageIfNeeded() async {
        guard item.uiImage == nil, let url = item.remoteURL else { return }
        loadedImage = nil
        loadFailed = false
        do {
            let (data, response) = try await URLSession.shared.data(from: url)
            guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode),
                  let image = UIImage(data: data) else {
                loadFailed = true
                return
            }
            loadedImage = image
        } catch {
            loadFailed = true
        }
    }
}

/// Onda de voz estilo WhatsApp / iOS: barras reales en lo reproducido, puntos en lo pendiente.
struct VoiceMessageWaveformStrip: View {
    let bars: [CGFloat]
    let progress: CGFloat
    var isLoading: Bool = false
    var accentColor: Color = GrooChatTheme.telegramBlue
    var stripHeight: CGFloat = 28
    var onSeek: ((CGFloat) -> Void)? = nil

    private var displayBars: [CGFloat] {
        if bars.isEmpty {
            return (0 ..< 28).map { i in
                0.18 + 0.42 * (0.5 + 0.5 * sin(Double(i) * 0.41))
            }
        }
        return bars
    }

    var body: some View {
        GeometryReader { geo in
            let width = geo.size.width
            let height = geo.size.height
            let count = displayBars.count
            let gap: CGFloat = 2.5
            let totalGaps = CGFloat(max(0, count - 1)) * gap
            let barW = max(2, (width - totalGaps) / CGFloat(count))
            let clampedProgress = min(1, max(0, progress))

            ZStack(alignment: .leading) {
                HStack(alignment: .center, spacing: gap) {
                    ForEach(Array(displayBars.enumerated()), id: \.offset) { index, amplitude in
                        let segment = count > 1 ? CGFloat(index) / CGFloat(count - 1) : 0
                        let played = segment <= clampedProgress

                        if played {
                            RoundedRectangle(cornerRadius: min(2, barW * 0.5), style: .continuous)
                                .fill(accentColor.opacity(0.35 + 0.55 * Double(amplitude)))
                                .frame(
                                    width: barW,
                                    height: max(3, amplitude * height)
                                )
                                .frame(height: height, alignment: .center)
                        } else {
                            Circle()
                                .fill(Color.black.opacity(isLoading ? 0.12 : 0.2))
                                .frame(width: min(3.5, barW), height: min(3.5, barW))
                                .frame(width: barW, height: height, alignment: .center)
                        }
                    }
                }
                .frame(width: width, height: height, alignment: .center)

                if clampedProgress > 0.01, !isLoading {
                    Circle()
                        .fill(accentColor)
                        .frame(width: 8, height: 8)
                        .shadow(color: accentColor.opacity(0.35), radius: 2, y: 1)
                        .offset(x: scrubberX(width: width, progress: clampedProgress))
                }
            }
            .frame(width: width, height: height)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onEnded { value in
                        guard let onSeek else { return }
                        let fraction = min(1, max(0, value.location.x / max(width, 1)))
                        onSeek(fraction)
                    }
            )
        }
        .frame(height: stripHeight)
    }

    private func scrubberX(width: CGFloat, progress: CGFloat) -> CGFloat {
        min(max(0, progress * width - 4), max(0, width - 8))
    }
}

struct GrooMessageBubbleView: View {
    let text: String
    let time: Date
    let isOutgoing: Bool
    let isLastInGroup: Bool
    var delivery: GrooMessageDeliveryStatus = .none
    var isStreaming: Bool = false
    var image: UIImage? = nil
    var onImageTap: (() -> Void)? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(maxWidth: .infinity)
                    .frame(height: 200)
                    .clipped()
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .onTapGesture {
                        onImageTap?()
                    }
            }

            if !trimmedText.isEmpty {
                textWithInlineMeta
            } else if image != nil {
                metaRow
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background {
            GrooMessageBubbleShape(isOutgoing: isOutgoing, isLastInGroup: isLastInGroup)
                .fill(isOutgoing ? GrooChatTheme.outgoingBubble : GrooChatTheme.incomingBubble)
                .shadow(color: .black.opacity(0.07), radius: 3, y: 1)
        }
        .frame(maxWidth: min(UIScreen.main.bounds.width * 0.78, 320), alignment: isOutgoing ? .trailing : .leading)
    }

    private var trimmedText: String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Texto + hora/checks al estilo Telegram (meta abajo a la derecha dentro de la burbuja).
    private var textWithInlineMeta: some View {
        Text(trimmedText)
            .font(.system(size: 16, weight: .regular))
            .foregroundStyle(isOutgoing ? GrooChatTheme.outgoingText : GrooChatTheme.incomingText)
            .lineSpacing(2)
            .multilineTextAlignment(.leading)
            .padding(.trailing, metaReserveWidth)
            .padding(.bottom, 2)
            .overlay(alignment: .bottomTrailing) {
                metaRow
            }
            .overlay(alignment: .trailing) {
                if isStreaming {
                    ProgressView().scaleEffect(0.55).padding(.trailing, 2)
                }
            }
    }

    private var metaReserveWidth: CGFloat {
        // Reserva espacio para que el texto no choque con la hora/checks
        isOutgoing ? 72 : 52
    }

    private var metaRow: some View {
        HStack(spacing: 3) {
            Text(time.formatted(date: .omitted, time: .shortened))
                .font(.system(size: 11, weight: .regular))
                .foregroundStyle(isOutgoing ? GrooChatTheme.outgoingMeta : GrooChatTheme.metaText)
            if isOutgoing { deliveryIcon }
        }
    }

    @ViewBuilder
    private var deliveryIcon: some View {
        switch delivery {
        case .none:
            EmptyView()
        case .sent:
            Image(systemName: "checkmark")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(GrooChatTheme.outgoingMeta)
        case .delivered:
            HStack(spacing: -4) {
                Image(systemName: "checkmark")
                Image(systemName: "checkmark")
            }
            .font(.system(size: 10, weight: .bold))
            .foregroundStyle(GrooChatTheme.outgoingMeta)
        case .read:
            HStack(spacing: -4) {
                Image(systemName: "checkmark")
                Image(systemName: "checkmark")
            }
            .font(.system(size: 10, weight: .bold))
            .foregroundStyle(GrooChatTheme.readChecks)
        }
    }
}

struct GrooTypingIndicatorBubble: View {
    var body: some View {
        TimelineView(.animation(minimumInterval: 0.35)) { timeline in
            let phase = Int(timeline.date.timeIntervalSinceReferenceDate / 0.35) % 3
            HStack(spacing: 5) {
                ForEach(0..<3, id: \.self) { i in
                    Circle()
                        .fill(GrooBrand.primary.opacity(0.5))
                        .frame(width: 7, height: 7)
                        .offset(y: phase == i ? -3 : 0)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .background {
                GrooMessageBubbleShape(isOutgoing: false, isLastInGroup: true)
                    .fill(GrooChatTheme.incomingBubble)
                    .shadow(color: .black.opacity(0.06), radius: 6, y: 2)
            }
        }
    }
}

struct GrooChatDatePill: View {
    let label: String

    var body: some View {
        Text(label)
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(GrooChatTheme.metaText)
            .padding(.horizontal, 14)
            .padding(.vertical, 6)
            .background {
                Capsule(style: .continuous)
                    .fill(.ultraThinMaterial)
                    .overlay(Capsule().strokeBorder(Color.white.opacity(0.7), lineWidth: 0.5))
            }
    }
}

struct GrooChatPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .opacity(configuration.isPressed ? 0.92 : 1)
            .animation(.spring(response: 0.28, dampingFraction: 0.78), value: configuration.isPressed)
    }
}

struct GrooInboxConversationRow: View {
    let title: String
    let preview: String
    let date: Date
    var timeLabel: String? = nil
    var unreadCount: Int = 0
    var isPinned: Bool = false
    var avatarURL: URL? = nil
    var avatarAccessToken: String? = nil
    var avatarInitial: String? = nil
    var socialSource: ChatSocialPlatform? = nil

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            GrooInboxAvatarView(
                title: title,
                avatarURL: avatarURL,
                avatarAccessToken: avatarAccessToken,
                avatarInitial: avatarInitial,
                socialSource: socialSource,
                size: 54
            )

            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(title)
                        .font(.system(size: 17, weight: unreadCount > 0 ? .semibold : .regular))
                        .foregroundStyle(Color.black.opacity(0.92))
                        .lineLimit(1)
                    Spacer(minLength: 6)
                    Text(timeLabel ?? relativeDate(date))
                        .font(.system(size: 14, weight: .regular))
                        .foregroundStyle(unreadCount > 0 ? GrooChatTheme.telegramBlue : Color.black.opacity(0.35))
                }

                HStack(alignment: .center, spacing: 8) {
                    if isPinned && unreadCount == 0 {
                        Image(systemName: "pin.fill")
                            .font(.system(size: 11))
                            .foregroundStyle(Color.black.opacity(0.28))
                    }
                    Text(preview.isEmpty ? " " : preview)
                        .font(.system(size: 15, weight: .regular))
                        .foregroundStyle(Color.black.opacity(0.4))
                        .lineLimit(1)
                    Spacer(minLength: 4)
                    if unreadCount > 0 {
                        Text("\(min(unreadCount, 99))")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 7)
                            .frame(minWidth: 22, minHeight: 22)
                            .background(Capsule().fill(GrooChatTheme.unreadBadge))
                    }
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 7)
        .frame(minHeight: 70)
        .contentShape(Rectangle())
    }

    private func relativeDate(_ date: Date) -> String {
        let cal = Calendar.current
        if cal.isDateInToday(date) { return date.formatted(date: .omitted, time: .shortened) }
        if cal.isDateInYesterday(date) { return "Ayer" }
        let days = cal.dateComponents([.day], from: cal.startOfDay(for: date), to: cal.startOfDay(for: Date())).day ?? 99
        if days < 7 {
            return date.formatted(.dateTime.weekday(.abbreviated))
        }
        return date.formatted(.dateTime.day().month(.twoDigits).year(.twoDigits))
    }
}

// MARK: - Respuestas rápidas CRM (Instagram / WhatsApp)

struct GrooCrmQuickReply: Identifiable {
    let id: String
    let icon: String
    let label: String
    let message: String

    static func templates(for contactTitle: String) -> [GrooCrmQuickReply] {
        let name = Self.contactFirstName(from: contactTitle)
        return [
            GrooCrmQuickReply(
                id: "appointment-today",
                icon: "calendar",
                label: "Cita hoy",
                message: """
                ¡Hola\(name.isEmpty ? "" : ", \(name)")! 👋 Tenemos disponibilidad para agendar tu consulta gratuita hoy. \
                Cuéntanos tu nombre completo, el servicio que te interesa y el horario que prefieres (mañana o tarde). \
                Uno de nuestros especialistas te confirmará la cita muy pronto 😊
                """
            ),
            GrooCrmQuickReply(
                id: "follow-up",
                icon: "person.2.fill",
                label: "Seguimiento",
                message: """
                Hola\(name.isEmpty ? "" : ", \(name)")! ¿Cómo te has sentido después de tu última visita? \
                Cuéntanos si necesitas algo más o si quieres que revisemos tu plan de tratamiento.
                """
            ),
            GrooCrmQuickReply(
                id: "products",
                icon: "bag.fill",
                label: "Productos",
                message: """
                Hola\(name.isEmpty ? "" : ", \(name)")! Te comparto nuestros productos recomendados:
                • NAD+ Recovery
                • Energy Focus
                • Sleep Wellness
                ¿Cuál te interesa? Te enviamos precio y disponibilidad al momento 🙌
                """
            ),
            GrooCrmQuickReply(
                id: "payment",
                icon: "dollarsign.circle",
                label: "Enlaces pago",
                message: """
                Hola\(name.isEmpty ? "" : ", \(name)")! Puedes pagar en línea con el enlace de tu servicio:

                ⭐ VIP Concierge
                https://checkout.square.site/merchant/EJG2FZH297AY2/checkout/LVPNZ7VVI3FA6T7RVBNVZLPU?src=sheet

                🦷 Consulta Ortho
                https://checkout.square.site/merchant/EJG2FZH297AY2/checkout/UD6FUVSIYJXPZLYPBB6IRNK5?src=sheet

                ✨ Limited Concierge — Smile Studio Doral
                https://checkout.square.site/merchant/EJG2FZH297AY2/checkout/SKC5GROJTH56NQPLVEYY5EAZ?src=sheet

                También aceptamos Zelle: drgprivate@drgsmile.com

                Cuando pagues, envíanos el comprobante por aquí para verificarlo 🙏
                """
            ),
            GrooCrmQuickReply(
                id: "reminder",
                icon: "bell.fill",
                label: "Recordatorio",
                message: """
                Hola\(name.isEmpty ? "" : ", \(name)")! Te recordamos tu cita programada con nosotros. \
                Si necesitas cambiarla, avísanos con gusto y te proponemos otro horario 🙏
                """
            ),
        ]
    }

    private static func contactFirstName(from title: String) -> String {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("@") {
            return String(trimmed.dropFirst())
        }
        if let segment = trimmed.split(separator: "·").last {
            let part = segment.trimmingCharacters(in: .whitespaces)
            if part.hasPrefix("@") { return String(part.dropFirst()) }
            return part
        }
        return trimmed.split(separator: " ").first.map(String.init) ?? trimmed
    }
}

struct GrooCrmQuickRepliesBar: View {
    let contactTitle: String
    var isDisabled: Bool = false
    var onSelect: (GrooCrmQuickReply) -> Void

    private var replies: [GrooCrmQuickReply] {
        GrooCrmQuickReply.templates(for: contactTitle)
    }

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(replies) { reply in
                    Button {
                        onSelect(reply)
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: reply.icon)
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(GrooBrand.primary)
                                .frame(width: 28, height: 28)
                                .background(Circle().fill(GrooBrand.primarySoft.opacity(0.85)))
                            Text(reply.label)
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(Color.black.opacity(0.78))
                                .lineLimit(1)
                        }
                        .padding(.leading, 6)
                        .padding(.trailing, 14)
                        .padding(.vertical, 6)
                        .background { GrooChatTheme.glassPillBackground() }
                    }
                    .buttonStyle(GrooChatPressStyle())
                    .disabled(isDisabled)
                }
            }
            .padding(.horizontal, 14)
            .padding(.top, 10)
            .padding(.bottom, 4)
        }
        .scrollIndicators(.hidden)
    }
}

struct GrooChatComposerBar: View {
    @Binding var text: String
    var isSending: Bool
    var focused: FocusState<Bool>.Binding
    var onSend: () -> Void
    var showsBlurBackground: Bool = true

    private var isEmpty: Bool {
        text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var isMultiline: Bool {
        text.contains(where: \.isNewline) || text.count > 36
    }

    private var canSend: Bool {
        !isEmpty && !isSending
    }

    var body: some View {
        HStack(alignment: isMultiline ? .bottom : .center, spacing: 8) {
            attachmentButton
            messageField
            sendOrMicButton
        }
        .padding(.horizontal, 10)
        .padding(.top, showsBlurBackground ? 10 : 4)
        .padding(.bottom, 8)
        .fixedSize(horizontal: false, vertical: true)
        .background {
            if showsBlurBackground {
                GrooChatTheme.floatingBlurChromeBottom()
                    .ignoresSafeArea(edges: .bottom)
            }
        }
        .animation(.easeInOut(duration: 0.15), value: isMultiline)
        .animation(.easeInOut(duration: 0.15), value: isEmpty)
    }

    private var attachmentButton: some View {
        Button {} label: {
            Image(systemName: "paperclip")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(Color.black.opacity(0.65))
                .frame(width: 40, height: 40)
                .background { GrooChatTheme.glassCircleBackground() }
        }
        .buttonStyle(.plain)
    }

    private var messageField: some View {
        HStack(alignment: isMultiline ? .bottom : .center, spacing: 8) {
            TextField("Mensaje", text: $text, axis: .vertical)
                .lineLimit(1...6)
                .focused(focused)
                .font(.system(size: 16))
                .submitLabel(.send)
                .onSubmit { if canSend { onSend() } }
                .frame(maxWidth: .infinity, alignment: .leading)

            Button {} label: {
                Image(systemName: "face.smiling")
                    .font(.system(size: 20, weight: .regular))
                    .foregroundStyle(Color.black.opacity(0.35))
                    .frame(width: 28, height: 28)
            }
            .buttonStyle(.plain)
        }
        .padding(.leading, 14)
        .padding(.trailing, 10)
        .padding(.vertical, isMultiline ? 10 : 8)
        .frame(maxWidth: .infinity)
        .frame(minHeight: 40, maxHeight: isEmpty ? 40 : 160, alignment: isMultiline ? .bottom : .center)
        .background { fieldBackground }
    }

    @ViewBuilder
    private var fieldBackground: some View {
        if isEmpty || !isMultiline {
            Capsule(style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay(Capsule().fill(Color.white.opacity(0.88)))
                .overlay(Capsule().strokeBorder(Color.white.opacity(0.98), lineWidth: 1))
                .shadow(color: .black.opacity(0.08), radius: 8, y: 2)
        } else {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay {
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .fill(Color.white.opacity(0.88))
                }
                .overlay {
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.98), lineWidth: 1)
                }
                .shadow(color: .black.opacity(0.08), radius: 8, y: 2)
        }
    }

    private var sendOrMicButton: some View {
        Button(action: onSend) {
            Image(systemName: canSend ? "arrow.up" : "mic.fill")
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(canSend ? Color.white : Color.black.opacity(0.65))
                .frame(width: 40, height: 40)
                .background {
                    if canSend {
                        Circle()
                            .fill(GrooChatTheme.telegramBlue)
                            .shadow(color: GrooChatTheme.telegramBlue.opacity(0.3), radius: 8, y: 2)
                    } else {
                        GrooChatTheme.glassCircleBackground()
                    }
                }
        }
        .buttonStyle(GrooChatPressStyle())
        .disabled(isSending)
    }
}

// MARK: - Contexto clínico en chat con paciente

struct GrooPatientChatContextPanel: View {
    let patient: GrooPatient
    @ObservedObject var groo: GrooAppStore
    var onSchedule: () -> Void
    var onOpenProfile: () -> Void
    var onBudget: () -> Void

    @State private var showDetails = false

    private var lastVisit: GrooClinicalRecord? {
        groo.lastClinicalRecord(for: patient.id)
    }

    private var nextReminder: GrooReminder? {
        groo.upcomingReminder(for: patient.id)
    }

    private var lastVisitShort: String {
        guard let last = lastVisit else { return "Sin visita" }
        return "\(groo.formattedClinicalDateShort(last.date)) · \(last.title)"
    }

    private var nextApptShort: String {
        if let next = nextReminder {
            return groo.formattedClinicalDateShort(next.dueAt)
        }
        if let next = patient.nextAppointment {
            return groo.formattedClinicalDateShort(next)
        }
        return "Sin cita"
    }

    var body: some View {
        VStack(spacing: 5) {
            HStack(spacing: 8) {
                compactPill(icon: "clock.arrow.circlepath", text: lastVisitShort)
                    .frame(maxWidth: .infinity, alignment: .leading)

                compactPill(icon: "calendar", text: nextApptShort)
                    .frame(maxWidth: .infinity, alignment: .leading)

                Button(action: onSchedule) {
                    Image(systemName: "calendar.badge.plus")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 34, height: 34)
                        .background(Circle().fill(GrooBrand.primary))
                }
                .buttonStyle(.plain)

                Button(action: onBudget) {
                    Image(systemName: "doc.richtext.fill")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(GrooBrand.primary)
                        .frame(width: 34, height: 34)
                        .background(Circle().fill(GrooBrand.primarySoft))
                }
                .buttonStyle(.plain)

                Button { showDetails = true } label: {
                    Image(systemName: "info.circle")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(GrooBrand.primary.opacity(0.85))
                        .frame(width: 28, height: 34)
                }
                .buttonStyle(.plain)
            }

            HStack(spacing: 8) {
                paymentPill(
                    icon: "dollarsign.circle.fill",
                    label: "Cobrado",
                    value: groo.formattedTotalEarnedFromPatient(patient.id),
                    tint: DrflowTheme.positive
                )
                paymentPill(
                    icon: "exclamationmark.circle.fill",
                    label: "Debe",
                    value: groo.formattedPendingBalance(for: patient.id),
                    tint: groo.pendingBalance(for: patient.id) > 0 ? Color.orange : DrflowTheme.textSecondary
                )
                if let last = lastVisit {
                    paymentPill(
                        icon: "tag.fill",
                        label: "Última",
                        value: groo.formattedClinicalUSD(last.amountPaid),
                        tint: GrooBrand.primary
                    )
                }
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color.white.opacity(0.72))
                }
                .overlay {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.85), lineWidth: 0.6)
                }
                .shadow(color: .black.opacity(0.05), radius: 6, y: -1)
        }
        .padding(.horizontal, 10)
        .padding(.top, 4)
        .padding(.bottom, 0)
        .sheet(isPresented: $showDetails) {
            GrooPatientChatDetailSheet(
                patient: patient,
                groo: groo,
                onOpenProfile: onOpenProfile,
                onSchedule: {
                    showDetails = false
                    onSchedule()
                },
                onBudget: {
                    showDetails = false
                    onBudget()
                }
            )
            .presentationDetents([.medium])
            .presentationDragIndicator(.visible)
        }
    }

    private func compactPill(icon: String, text: String) -> some View {
        HStack(spacing: 5) {
            Image(systemName: icon)
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(GrooBrand.primary)
            Text(text)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(DrflowTheme.textPrimary)
                .lineLimit(1)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background {
            Capsule().fill(GrooBrand.primarySoft.opacity(0.65))
        }
    }

    private func paymentPill(icon: String, label: String, value: String, tint: Color) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 8, weight: .bold))
                .foregroundStyle(tint)
            VStack(alignment: .leading, spacing: 0) {
                Text(label)
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(DrflowTheme.textTertiary)
                Text(value)
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(tint)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(tint.opacity(0.08))
        }
    }
}

private struct GrooPatientChatDetailSheet: View {
    let patient: GrooPatient
    @ObservedObject var groo: GrooAppStore
    var onOpenProfile: () -> Void
    var onSchedule: () -> Void
    var onBudget: () -> Void
    @Environment(\.dismiss) private var dismiss

    private var history: [GrooClinicalRecord] {
        Array(groo.clinicalHistory(for: patient.id).prefix(4))
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    HStack(spacing: 0) {
                        chatPaymentCell(
                            title: "Cobrado",
                            value: groo.formattedTotalEarnedFromPatient(patient.id),
                            tint: DrflowTheme.positive
                        )
                        Divider().frame(height: 40)
                        chatPaymentCell(
                            title: "Debe",
                            value: groo.formattedPendingBalance(for: patient.id),
                            tint: groo.pendingBalance(for: patient.id) > 0 ? Color.orange : DrflowTheme.textSecondary
                        )
                        Divider().frame(height: 40)
                        chatPaymentCell(
                            title: "Precio total",
                            value: groo.formattedTotalQuoted(for: patient.id),
                            tint: GrooBrand.primary
                        )
                    }
                    .padding(.vertical, 10)
                    .padding(.horizontal, 8)
                    .background {
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(GrooBrand.primarySoft.opacity(0.45))
                    }

                    if let last = groo.lastClinicalRecord(for: patient.id) {
                        detailBlock(
                            title: "Última visita",
                            lines: [
                                groo.formattedClinicalDate(last.date),
                                last.title,
                                "\(last.doctorDisplay) · \(last.roomDisplay) · \(last.formattedDuration)",
                                "Precio \(groo.formattedClinicalUSD(last.servicePrice)) · Pagó \(groo.formattedClinicalUSD(last.amountPaid))"
                                    + (last.pendingAmount > 0.01 ? " · Debe \(groo.formattedClinicalUSD(last.pendingAmount))" : ""),
                            ]
                        )
                    }
                    if let next = groo.upcomingReminder(for: patient.id) {
                        detailBlock(
                            title: "Próxima cita",
                            lines: [groo.formattedClinicalDate(next.dueAt), next.title]
                        )
                    }
                    if !history.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Historial y pagos")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundStyle(DrflowTheme.textTertiary)
                            ForEach(history) { record in
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("\(groo.formattedClinicalDateShort(record.date)): \(record.title)")
                                        .font(.system(size: 13, weight: .semibold))
                                        .foregroundStyle(DrflowTheme.textPrimary)
                                    Text(
                                        "Precio \(groo.formattedClinicalUSD(record.servicePrice)) · Pagó \(groo.formattedClinicalUSD(record.amountPaid))"
                                        + (record.pendingAmount > 0.01 ? " · Debe \(groo.formattedClinicalUSD(record.pendingAmount))" : " · Pagado")
                                    )
                                    .font(.system(size: 11, weight: .medium))
                                    .foregroundStyle(record.pendingAmount > 0.01 ? Color.orange : DrflowTheme.textSecondary)
                                }
                            }
                        }
                    }
                    HStack(spacing: 10) {
                        Button("Agendar cita", action: onSchedule)
                            .buttonStyle(.borderedProminent)
                            .tint(GrooBrand.primary)
                        Button("Presupuesto PDF", action: onBudget)
                            .buttonStyle(.borderedProminent)
                            .tint(Color(red: 0.12, green: 0.58, blue: 0.28))
                        Button("Ver ficha", action: onOpenProfile)
                            .buttonStyle(.bordered)
                            .tint(GrooBrand.primary)
                    }
                }
                .padding(16)
            }
            .navigationTitle(patient.fullName)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Cerrar") { dismiss() }
                }
            }
        }
    }

    private func detailBlock(title: String, lines: [String]) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(DrflowTheme.textTertiary)
            ForEach(lines, id: \.self) { line in
                Text(line)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(DrflowTheme.textPrimary)
            }
        }
    }

    private func chatPaymentCell(title: String, value: String, tint: Color) -> some View {
        VStack(spacing: 3) {
            Text(title)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(DrflowTheme.textTertiary)
            Text(value)
                .font(.system(size: 15, weight: .bold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(tint)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .frame(maxWidth: .infinity)
    }
}
