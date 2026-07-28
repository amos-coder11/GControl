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

    static let listBackground = DrflowTheme.background
    static let wallpaperTop = Color(red: 0.94, green: 0.97, blue: 1.0)
    static let wallpaperBottom = Color(red: 0.90, green: 0.94, blue: 0.99)

    static let outgoingBubble = Color(red: 0.78, green: 0.88, blue: 1.0)
    static let outgoingBubbleEdge = Color(red: 0.62, green: 0.76, blue: 0.98)
    static let incomingBubble = Color.white
    static let sendButton = GrooBrand.primary
    static let outgoingText = Color(red: 0.07, green: 0.10, blue: 0.20)
    static let incomingText = Color(red: 0.07, green: 0.10, blue: 0.20)
    static let metaText = Color.black.opacity(0.38)
    static let composerBar = Color.white
    static let separator = Color.black.opacity(0.06)
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
        ZStack {
            LinearGradient(
                colors: [GrooChatTheme.wallpaperTop, GrooChatTheme.wallpaperBottom],
                startPoint: .top,
                endPoint: .bottom
            )
            Canvas { context, size in
                let step: CGFloat = 28
                for x in stride(from: 0, through: size.width, by: step) {
                    for y in stride(from: 0, through: size.height, by: step) {
                        let rect = CGRect(x: x, y: y, width: 2, height: 2)
                        context.fill(Path(ellipseIn: rect), with: .color(Color.black.opacity(0.025)))
                    }
                }
            }
            .allowsHitTesting(false)
        }
    }
}

// MARK: - Avatar

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

struct GrooClinicChatContact: Identifiable {
    let id: String
    let name: String
    let role: String
    let symbol: String
    let tint: Color
}

enum GrooClinicContacts {
    static let pinned: [GrooClinicChatContact] = [
        .init(id: "groo", name: "\(GrooBrand.appName) Assistant", role: "AI · Clinic ops", symbol: "sparkles", tint: GrooBrand.primary),
        .init(id: "front", name: "Front Desk", role: "Appointments", symbol: "calendar", tint: Color(red: 0.2, green: 0.55, blue: 0.95)),
        .init(id: "billing", name: "Billing", role: "Collections", symbol: "dollarsign.circle", tint: Color(red: 0.15, green: 0.65, blue: 0.55)),
    ]
}

// MARK: - Bubble shape

enum GrooMessageDeliveryStatus {
    case none, sent, delivered, read
}

struct GrooMessageBubbleShape: Shape {
    var isOutgoing: Bool
    var isLastInGroup: Bool

    func path(in rect: CGRect) -> Path {
        let r: CGFloat = 18
        let tail: CGFloat = isLastInGroup ? 5 : r
        var corners = RectangleCornerRadii(topLeading: r, bottomLeading: r, bottomTrailing: r, topTrailing: r)
        if isOutgoing {
            corners.bottomTrailing = tail
        } else {
            corners.bottomLeading = tail
        }
        return UnevenRoundedRectangle(cornerRadii: corners, style: .continuous).path(in: rect)
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

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(maxWidth: .infinity)
                    .frame(height: 220)
                    .clipped()
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .padding(.horizontal, 8)
                    .padding(.top, 8)
            }

            if !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Text(text)
                    .font(.system(size: 16, weight: .regular))
                    .foregroundStyle(isOutgoing ? GrooChatTheme.outgoingText : GrooChatTheme.incomingText)
                    .lineSpacing(3)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 12)
                    .padding(.top, image == nil ? 9 : 8)
                    .padding(.bottom, 22)
            } else {
                Color.clear.frame(height: 22)
            }

            HStack(spacing: 4) {
                if isStreaming {
                    ProgressView().scaleEffect(0.55)
                }
                Spacer(minLength: 0)
                Text(time.formatted(date: .omitted, time: .shortened))
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(GrooChatTheme.metaText)
                if isOutgoing { deliveryIcon }
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 8)
        }
        .background {
            GrooMessageBubbleShape(isOutgoing: isOutgoing, isLastInGroup: isLastInGroup)
                .fill(bubbleFill)
                .shadow(color: .black.opacity(isOutgoing ? 0.04 : 0.07), radius: 8, y: 3)
                .overlay {
                    if isOutgoing {
                        GrooMessageBubbleShape(isOutgoing: true, isLastInGroup: isLastInGroup)
                            .stroke(GrooChatTheme.outgoingBubbleEdge.opacity(0.35), lineWidth: 0.5)
                    }
                }
        }
        .frame(maxWidth: min(UIScreen.main.bounds.width * 0.76, 340), alignment: isOutgoing ? .trailing : .leading)
    }

    private var bubbleFill: some ShapeStyle {
        isOutgoing ? AnyShapeStyle(GrooChatTheme.outgoingBubble) : AnyShapeStyle(GrooChatTheme.incomingBubble)
    }

    @ViewBuilder
    private var deliveryIcon: some View {
        switch delivery {
        case .none: EmptyView()
        case .sent:
            Image(systemName: "checkmark").font(.system(size: 10, weight: .bold)).foregroundStyle(GrooChatTheme.metaText)
        case .delivered, .read:
            HStack(spacing: -5) {
                Image(systemName: "checkmark")
                Image(systemName: "checkmark")
            }
            .font(.system(size: 10, weight: .bold))
            .foregroundStyle(delivery == .read ? GrooBrand.primary : GrooChatTheme.metaText)
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
    var unreadCount: Int = 0
    var isPinned: Bool = false
    var avatarURL: URL? = nil
    var avatarAccessToken: String? = nil
    var avatarInitial: String? = nil
    var showsInstagramBadge: Bool = false

    var body: some View {
        HStack(spacing: 14) {
            ZStack(alignment: .bottomTrailing) {
                if let avatarURL {
                    ChatAsyncContactPhoto(
                        url: avatarURL,
                        accessToken: avatarAccessToken,
                        fallbackInitial: avatarInitial ?? String(title.prefix(1)),
                        fallbackColor: Color(red: 0.69, green: 0.32, blue: 0.87),
                        diameter: 54
                    )
                } else {
                    GrooChatAvatar(size: 54, showsOnlineRing: isPinned)
                }
                if showsInstagramBadge {
                    ChatSocialBadgeView(platform: .instagram)
                        .frame(width: 18, height: 18)
                        .offset(x: 2, y: 2)
                }
            }

            VStack(alignment: .leading, spacing: 5) {
                HStack(alignment: .firstTextBaseline) {
                    Text(title)
                        .font(.system(size: 16, weight: unreadCount > 0 ? .bold : .semibold))
                        .foregroundStyle(Color.black.opacity(0.88))
                        .lineLimit(1)
                    Spacer(minLength: 8)
                    Text(relativeDate(date))
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(unreadCount > 0 ? GrooBrand.primary : GrooChatTheme.metaText)
                }

                HStack(alignment: .center, spacing: 8) {
                    Text(preview)
                        .font(.system(size: 14, weight: unreadCount > 0 ? .medium : .regular))
                        .foregroundStyle(Color.black.opacity(unreadCount > 0 ? 0.55 : 0.42))
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                    Spacer(minLength: 0)
                    if unreadCount > 0 {
                        Text("\(min(unreadCount, 99))")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(.white)
                            .frame(minWidth: 22, minHeight: 22)
                            .background(Circle().fill(GrooBrand.primary))
                    } else if isPinned {
                        Image(systemName: "pin.fill")
                            .font(.system(size: 11))
                            .foregroundStyle(GrooBrand.primary.opacity(0.7))
                    }
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 13)
        .contentShape(Rectangle())
    }

    private func relativeDate(_ date: Date) -> String {
        let cal = Calendar.current
        if cal.isDateInToday(date) { return date.formatted(date: .omitted, time: .shortened) }
        if cal.isDateInYesterday(date) { return "Yesterday" }
        return date.formatted(.dateTime.month(.abbreviated).day())
    }
}

struct GrooChatComposerBar: View {
    @Binding var text: String
    var isSending: Bool
    var focused: FocusState<Bool>.Binding
    var onSend: () -> Void

    var body: some View {
        HStack(alignment: .bottom, spacing: 10) {
            Button {} label: {
                Image(systemName: "plus.circle.fill")
                    .font(.system(size: 28))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(GrooBrand.primary)
            }
            .buttonStyle(.plain)

            HStack(alignment: .bottom, spacing: 8) {
                TextField("Message", text: $text, axis: .vertical)
                    .lineLimit(1...6)
                    .focused(focused)
                    .font(.system(size: 16))
                    .submitLabel(.send)
                    .onSubmit { if canSend { onSend() } }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background {
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(Color(red: 0.96, green: 0.97, blue: 0.99))
                    .overlay {
                        RoundedRectangle(cornerRadius: 22, style: .continuous)
                            .strokeBorder(GrooChatTheme.separator, lineWidth: 0.5)
                    }
            }

            Button(action: onSend) {
                Image(systemName: canSend ? "arrow.up.circle.fill" : "mic.circle.fill")
                    .font(.system(size: 34))
                    .symbolRenderingMode(.palette)
                    .foregroundStyle(.white, canSend ? GrooBrand.primary : Color.black.opacity(0.25))
            }
            .buttonStyle(GrooChatPressStyle())
            .disabled(isSending)
        }
        .padding(.horizontal, 12)
        .padding(.top, 10)
        .padding(.bottom, 8)
        .background {
            GrooChatTheme.composerBar
                .shadow(color: .black.opacity(0.06), radius: 12, y: -4)
                .ignoresSafeArea(edges: .bottom)
        }
    }

    private var canSend: Bool {
        !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !isSending
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
                .fill(Color.white.opacity(0.95))
                .shadow(color: .black.opacity(0.05), radius: 6, y: -1)
        }
        .padding(.horizontal, 10)
        .padding(.bottom, 2)
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
