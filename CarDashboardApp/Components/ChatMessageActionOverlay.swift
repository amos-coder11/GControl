import SwiftUI
import UIKit

// MARK: - Actions

enum ChatMessageMenuAction: Hashable {
    case reply
    case copy
    case edit
    case saveImage
    case report
    case block
}

struct ChatMessageMenuItem: Identifiable, Hashable {
    let title: String
    let systemImage: String
    let action: ChatMessageMenuAction
    var isDestructive: Bool = false

    var id: ChatMessageMenuAction { action }
}

// MARK: - Overlay

/// Menú de mensaje estilo Telegram: fondo difuminado, reacciones y acciones.
struct ChatMessageActionOverlay<Bubble: View>: View {
    let bubbleFrame: CGRect
    let isOutgoing: Bool
    let receiptCaption: String?
    let menuItems: [ChatMessageMenuItem]
    let reactions: [String]
    @ViewBuilder var bubble: () -> Bubble
    var onReaction: (String) -> Void
    var onAction: (ChatMessageMenuAction) -> Void
    var onDismiss: () -> Void

    @State private var appeared = false
    @State private var showAllReactions = false
    private let reactionBarHeight: CGFloat = 52
    private let menuWidth: CGFloat = 250
    private let gap: CGFloat = 10

    var body: some View {
        GeometryReader { geo in
            let layout = Self.layout(
                bubbleFrame: bubbleFrame,
                container: geo.size,
                reactionBarHeight: reactionBarHeight,
                menuEstimatedHeight: estimatedMenuHeight,
                gap: gap,
                isOutgoing: isOutgoing,
                menuWidth: menuWidth
            )

            ZStack {
                Rectangle()
                    .fill(.ultraThinMaterial)
                    .overlay(Color.black.opacity(appeared ? 0.18 : 0))
                    .ignoresSafeArea()
                    .opacity(appeared ? 1 : 0)
                    .allowsHitTesting(appeared)
                    .onTapGesture { dismiss() }

                VStack(spacing: gap) {
                    reactionBar
                        .scaleEffect(appeared ? 1 : 0.86, anchor: isOutgoing ? .bottomTrailing : .bottomLeading)
                        .opacity(appeared ? 1 : 0)
                        .offset(y: appeared ? 0 : 8)

                    bubble()
                        .frame(width: bubbleFrame.width, height: bubbleFrame.height, alignment: isOutgoing ? .trailing : .leading)
                        .shadow(color: .black.opacity(appeared ? 0.18 : 0), radius: 18, y: 10)
                        .scaleEffect(appeared ? 1.02 : 1.0)

                    actionMenu
                        .frame(width: menuWidth, alignment: isOutgoing ? .trailing : .leading)
                        .frame(maxWidth: .infinity, alignment: isOutgoing ? .trailing : .leading)
                        .scaleEffect(appeared ? 1 : 0.9, anchor: isOutgoing ? .topTrailing : .topLeading)
                        .opacity(appeared ? 1 : 0)
                        .offset(y: appeared ? 0 : -8)
                }
                .frame(width: max(bubbleFrame.width, menuWidth), alignment: isOutgoing ? .trailing : .leading)
                .position(x: layout.stackCenterX, y: layout.stackCenterY)
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
        .onAppear {
            UIImpactFeedbackGenerator(style: .rigid).impactOccurred()
            withAnimation(.spring(response: 0.34, dampingFraction: 0.86)) {
                appeared = true
            }
        }
        .confirmationDialog("Reacciones", isPresented: $showAllReactions, titleVisibility: .hidden) {
            ForEach(ChatMessageReactionCatalog.extra, id: \.self) { emoji in
                Button(emoji) { pickReaction(emoji) }
            }
            Button("Cancelar", role: .cancel) {}
        }
    }

    // MARK: Reaction bar

    private var reactionBar: some View {
        HStack(spacing: 2) {
            ForEach(reactions, id: \.self) { emoji in
                Button {
                    pickReaction(emoji)
                } label: {
                    Text(emoji)
                        .font(.system(size: 28))
                        .frame(width: 40, height: 40)
                        .contentShape(Rectangle())
                }
                .buttonStyle(ChatReactionPressStyle())
            }

            Button {
                showAllReactions = true
            } label: {
                Image(systemName: "chevron.down")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(Color.black.opacity(0.45))
                    .frame(width: 32, height: 32)
                    .background(Circle().fill(Color.black.opacity(0.06)))
            }
            .buttonStyle(.plain)
            .padding(.leading, 2)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background {
            Capsule(style: .continuous)
                .fill(.regularMaterial)
                .shadow(color: .black.opacity(0.12), radius: 16, y: 6)
        }
        .overlay(alignment: .bottom) {
            ChatReactionCaret()
                .fill(Color(uiColor: .systemBackground).opacity(0.92))
                .frame(width: 16, height: 8)
                .offset(y: 7)
                .allowsHitTesting(false)
        }
        .frame(maxWidth: .infinity, alignment: isOutgoing ? .trailing : .leading)
    }

    // MARK: Action menu

    private var actionMenu: some View {
        VStack(spacing: 0) {
            if let receiptCaption, !receiptCaption.isEmpty {
                HStack(spacing: 6) {
                    Image(systemName: "checkmark")
                        .font(.system(size: 9, weight: .bold))
                    Image(systemName: "checkmark")
                        .font(.system(size: 9, weight: .bold))
                        .offset(x: -6)
                    Text(receiptCaption)
                        .font(.system(size: 13, weight: .regular))
                    Spacer(minLength: 0)
                }
                .foregroundStyle(Color.secondary)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)

                Divider().opacity(0.35)
            }

            ForEach(Array(menuItems.enumerated()), id: \.element.id) { index, item in
                Button {
                    perform(item.action)
                } label: {
                    HStack(spacing: 12) {
                        Text(item.title)
                            .font(.system(size: 17, weight: .regular))
                            .foregroundStyle(item.isDestructive ? Color.red : Color.primary)
                        Spacer(minLength: 8)
                        Image(systemName: item.systemImage)
                            .font(.system(size: 17, weight: .regular))
                            .foregroundStyle(item.isDestructive ? Color.red : Color.primary.opacity(0.85))
                            .frame(width: 24, alignment: .center)
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
                    .contentShape(Rectangle())
                }
                .buttonStyle(ChatMenuRowPressStyle())

                if index < menuItems.count - 1 {
                    Divider().opacity(0.28)
                }
            }
        }
        .background {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(.regularMaterial)
                .shadow(color: .black.opacity(0.16), radius: 22, y: 10)
        }
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private var estimatedMenuHeight: CGFloat {
        let header: CGFloat = (receiptCaption?.isEmpty == false) ? 40 : 0
        return header + CGFloat(menuItems.count) * 46
    }

    private func pickReaction(_ emoji: String) {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        onReaction(emoji)
        dismiss()
    }

    private func perform(_ action: ChatMessageMenuAction) {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        onAction(action)
        dismiss()
    }

    private func dismiss() {
        withAnimation(.easeOut(duration: 0.18)) {
            appeared = false
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.16) {
            onDismiss()
        }
    }

    // MARK: Layout

    private struct Layout {
        var stackCenterX: CGFloat
        var stackCenterY: CGFloat
    }

    private static func layout(
        bubbleFrame: CGRect,
        container: CGSize,
        reactionBarHeight: CGFloat,
        menuEstimatedHeight: CGFloat,
        gap: CGFloat,
        isOutgoing: Bool,
        menuWidth: CGFloat
    ) -> Layout {
        let stackWidth = max(bubbleFrame.width, menuWidth)
        let stackHeight = reactionBarHeight + gap + bubbleFrame.height + gap + menuEstimatedHeight

        var originY = bubbleFrame.minY - reactionBarHeight - gap
        let minY: CGFloat = 16
        let maxY = container.height - stackHeight - 16
        if originY < minY { originY = minY }
        if originY > maxY { originY = max(minY, maxY) }

        let centerY = originY + stackHeight / 2

        let preferredTrailingX = bubbleFrame.maxX - stackWidth / 2
        let preferredLeadingX = bubbleFrame.minX + stackWidth / 2
        var centerX = isOutgoing ? preferredTrailingX : preferredLeadingX
        let half = stackWidth / 2
        centerX = min(max(centerX, half + 12), container.width - half - 12)

        return Layout(stackCenterX: centerX, stackCenterY: centerY)
    }
}

enum ChatMessageReactionCatalog {
    static let `default` = ["❤️", "👍", "👎", "🔥", "🥰", "👏", "😁"]
    static let extra = ["😂", "😮", "😢", "🙏", "🎉", "💯", "👀", "💪"]
}

// MARK: - Shapes / styles

private struct ChatReactionCaret: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.midX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        path.closeSubpath()
        return path
    }
}

private struct ChatReactionPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 1.22 : 1)
            .animation(.spring(response: 0.22, dampingFraction: 0.55), value: configuration.isPressed)
    }
}

private struct ChatMenuRowPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(configuration.isPressed ? Color.primary.opacity(0.06) : Color.clear)
    }
}

// MARK: - Frame tracking

struct ChatMessageFramePreferenceKey: PreferenceKey {
    static var defaultValue: [UUID: CGRect] = [:]

    static func reduce(value: inout [UUID: CGRect], nextValue: () -> [UUID: CGRect]) {
        value.merge(nextValue(), uniquingKeysWith: { $1 })
    }
}

/// Guarda frames sin `@State` para no invalidar el body del chat en cada scroll.
@MainActor
final class ChatMessageFrameStore {
    var frames: [UUID: CGRect] = [:]

    func frame(for id: UUID) -> CGRect? {
        frames[id]
    }

    func replaceAll(_ newFrames: [UUID: CGRect]) {
        frames = newFrames
    }
}

extension View {
    func chatMessageFrameTracker(id: UUID, coordinateSpace: CoordinateSpace) -> some View {
        background {
            GeometryReader { geo in
                Color.clear.preference(
                    key: ChatMessageFramePreferenceKey.self,
                    value: [id: geo.frame(in: coordinateSpace)]
                )
            }
        }
    }
}
