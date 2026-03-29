import SwiftUI

struct StatusBadge: View {
    let status: CarStatus

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(status.color)
                .frame(width: 7, height: 7)
                .shadow(color: status.color.opacity(0.6), radius: 4)

            Text(status.rawValue)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(status.color)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background {
            Capsule()
                .fill(status.color.opacity(0.12))
                .overlay {
                    Capsule()
                        .stroke(status.color.opacity(0.2), lineWidth: 0.5)
                }
        }
    }
}

#Preview {
    ZStack {
        Color.white.ignoresSafeArea()
        VStack(spacing: 12) {
            StatusBadge(status: .connected)
            StatusBadge(status: .disconnected)
            StatusBadge(status: .standby)
        }
    }
}
