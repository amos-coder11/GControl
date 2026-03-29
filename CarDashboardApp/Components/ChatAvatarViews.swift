import SwiftUI

// MARK: - Insignia red social (assets SVG + estilos para IG / WA / FB)

struct ChatSocialBadgeView: View {
    let platform: ChatSocialPlatform

    var body: some View {
        Group {
            switch platform {
            case .cochesNet:
                Image("BadgeCochesNet")
                    .resizable()
                    .scaledToFit()
            case .autoScout24:
                Image("BadgeAutoScout24")
                    .resizable()
                    .scaledToFit()
            case .wallapop:
                Image("BadgeWallapop")
                    .resizable()
                    .scaledToFit()
            case .instagram:
                ZStack {
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color(red: 0.98, green: 0.35, blue: 0.42),
                                    Color(red: 0.79, green: 0.22, blue: 0.72),
                                    Color(red: 0.39, green: 0.38, blue: 0.95)
                                ],
                                startPoint: .bottomLeading,
                                endPoint: .topTrailing
                            )
                        )
                    Image(systemName: "camera.fill")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.white)
                }
            case .whatsApp:
                ZStack {
                    Circle()
                        .fill(Color(red: 0.15, green: 0.78, blue: 0.41))
                    Image(systemName: "phone.fill")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.white)
                }
            case .facebook:
                ZStack {
                    Circle()
                        .fill(Color(red: 0.26, green: 0.40, blue: 0.85))
                    Text("f")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(.white)
                        .offset(y: -0.5)
                }
            }
        }
    }
}

// MARK: - Avatar lista / toolbar (foto coche + insignia)

struct ChatThreadAvatarView: View {
    let thread: ChatThread
    var diameter: CGFloat = 56

    private var badgeSize: CGFloat { max(18, diameter * 0.38) }

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            Group {
                if let url = thread.avatarCarURL {
                    ChatAsyncCarThumbnail(url: url)
                        .frame(width: diameter, height: diameter)
                        .clipShape(Circle())
                } else {
                    ZStack {
                        Circle()
                            .fill(thread.avatarColor)
                            .frame(width: diameter, height: diameter)
                        if let initial = thread.avatarInitial, let ch = initial.first {
                            Text(String(ch).uppercased())
                                .font(.system(size: diameter * 0.38, weight: .semibold))
                                .foregroundStyle(.white)
                        } else if let icon = thread.avatarIcon {
                            Image(systemName: icon)
                                .font(.system(size: diameter * 0.42, weight: .medium))
                                .foregroundStyle(.white)
                        }
                    }
                }
            }

            if thread.avatarCarURL != nil, let platform = thread.socialSource {
                ChatSocialBadgeView(platform: platform)
                    .frame(width: badgeSize - 4, height: badgeSize - 4)
                    .padding(2)
                    .background(Circle().fill(Color.white))
                    .clipShape(Circle())
                    .overlay {
                        Circle()
                            .strokeBorder(Color.white, lineWidth: 1.5)
                    }
                    .offset(x: diameter * 0.06, y: diameter * 0.06)
            }
        }
        .frame(width: diameter, height: diameter)
    }
}

// MARK: - Miniatura remota (misma idea que el showroom del dashboard)

private struct ChatAsyncCarThumbnail: View {
    let url: URL
    @State private var uiImage: UIImage?
    @State private var loadFailed = false

    var body: some View {
        Group {
            if let uiImage {
                Image(uiImage: uiImage)
                    .resizable()
                    .scaledToFill()
            } else if loadFailed {
                Color(white: 0.92)
                    .overlay {
                        Image(systemName: "car.fill")
                            .font(.title3)
                            .foregroundStyle(.tertiary)
                    }
            } else {
                Color(white: 0.94)
                    .overlay { ProgressView() }
            }
        }
        .frame(minWidth: 0, maxWidth: .infinity, minHeight: 0, maxHeight: .infinity)
        .clipped()
        .task(id: url) {
            await load()
        }
    }

    private func load() async {
        do {
            var request = URLRequest(url: url)
            request.cachePolicy = .returnCacheDataElseLoad
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse,
                  (200 ... 299).contains(http.statusCode),
                  let img = UIImage(data: data)
            else {
                await MainActor.run { loadFailed = true }
                return
            }
            await MainActor.run { uiImage = img }
        } catch {
            await MainActor.run { loadFailed = true }
        }
    }
}
