import SwiftUI

/// Slot aislado: observa el coordinator sin forzar rebuild del chat/inbox padre.
struct ChatVoiceMiniPlayerSlot: View {
    var bottomPadding: CGFloat = 0
    @ObservedObject private var playback = ChatVoicePlaybackCoordinator.shared

    var body: some View {
        Group {
            if playback.isActive {
                ChatVoiceMiniPlayerBar(playback: playback)
                    .padding(.bottom, bottomPadding)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.86), value: playback.isActive)
    }
}

/// Barra flotante estilo Telegram mientras suena una nota de voz.
struct ChatVoiceMiniPlayerBar: View {
    @ObservedObject var playback: ChatVoicePlaybackCoordinator

    var body: some View {
        if let session = playback.session {
            HStack(spacing: 12) {
                Button {
                    playback.togglePlayPause()
                } label: {
                    Image(systemName: playback.isPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(Color.black.opacity(0.85))
                        .frame(width: 28, height: 28)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                VStack(alignment: .leading, spacing: 2) {
                    Text(session.title)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Color.black.opacity(0.9))
                        .lineLimit(1)
                    Text(session.subtitle)
                        .font(.system(size: 12, weight: .regular))
                        .foregroundStyle(Color.black.opacity(0.45))
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Button {
                    playback.cycleRate()
                } label: {
                    VStack(spacing: 3) {
                        Capsule()
                            .fill(Color.black.opacity(0.28))
                            .frame(width: 18, height: 1.5)
                        Text(playback.rate.label)
                            .font(.system(size: 13, weight: .bold, design: .rounded))
                            .foregroundStyle(Color.black.opacity(0.8))
                            .monospacedDigit()
                        Capsule()
                            .fill(Color.black.opacity(0.28))
                            .frame(width: 18, height: 1.5)
                    }
                    .frame(width: 44, height: 36)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Velocidad \(playback.rate.label)")

                Button {
                    playback.dismiss()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(Color.black.opacity(0.55))
                        .frame(width: 28, height: 28)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Cerrar reproductor")
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background {
                Capsule(style: .continuous)
                    .fill(.ultraThinMaterial)
                    .overlay {
                        Capsule(style: .continuous)
                            .fill(Color.white.opacity(0.88))
                    }
                    .overlay(alignment: .bottom) {
                        TimelineView(
                            .animation(
                                minimumInterval: 1.0 / 30.0,
                                paused: !playback.isPlaying
                            )
                        ) { _ in
                            GeometryReader { geo in
                                Capsule()
                                    .fill(Color.black.opacity(0.85))
                                    .frame(width: max(4, geo.size.width * playback.progress), height: 2.5)
                                    .frame(maxHeight: .infinity, alignment: .bottom)
                            }
                            .frame(height: 2.5)
                            .clipShape(Capsule())
                            .padding(.horizontal, 10)
                            .padding(.bottom, 3)
                        }
                    }
                    .shadow(color: .black.opacity(0.12), radius: 14, y: 4)
            }
            .padding(.horizontal, 12)
            .transition(.move(edge: .top).combined(with: .opacity))
        }
    }
}
