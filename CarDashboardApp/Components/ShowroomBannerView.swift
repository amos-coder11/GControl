import SwiftUI

/// Banner con imagen remota del showroom (degradado inferior para legibilidad).
struct ShowroomBannerView: View {
    private let cornerRadius: CGFloat = 22

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            AsyncImage(url: RemoteAssets.carShowroomImageURL) { phase in
                switch phase {
                case .empty:
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .fill(Color.primary.opacity(0.06))
                        .overlay {
                            ProgressView()
                        }
                case .success(let image):
                    image
                        .resizable()
                        .scaledToFill()
                case .failure:
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .fill(Color.primary.opacity(0.08))
                        .overlay {
                            Image(systemName: "car.side.fill")
                                .font(.system(size: 36))
                                .foregroundStyle(.secondary)
                        }
                @unknown default:
                    Color.clear
                }
            }

            LinearGradient(
                colors: [
                    .black.opacity(0.55),
                    .black.opacity(0.2),
                    .clear
                ],
                startPoint: .bottom,
                endPoint: .top
            )
            .frame(height: 88)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
            .allowsHitTesting(false)

            Text("Showroom")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white.opacity(0.95))
                .padding(.horizontal, 14)
                .padding(.bottom, 12)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 152)
        .clipped()
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .stroke(Color.black.opacity(0.06), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.1), radius: 12, x: 0, y: 6)
    }
}

#Preview {
    ShowroomBannerView()
        .padding()
        .background(Color.gray.opacity(0.15))
}
