import SwiftUI

struct CarRow: View {
    let car: Car
    let isSelected: Bool
    var onTap: () -> Void = {}

    var accentColor: Color {
        switch car.color {
        case "orange": return .orange
        case "mint": return .mint
        default: return .cyan
        }
    }

    var body: some View {
        Button(action: onTap) {
            GlassCard(cornerRadius: 22, padding: 16) {
                HStack(spacing: 16) {
                    // Car icon
                    ZStack {
                        Circle()
                            .fill(accentColor.opacity(0.15))
                            .frame(width: 52, height: 52)

                        Image(systemName: car.icon)
                            .font(.system(size: 22, weight: .semibold))
                            .foregroundStyle(accentColor)
                    }

                    // Info
                    VStack(alignment: .leading, spacing: 4) {
                        Text(car.name)
                            .font(.system(size: 16, weight: .bold))
                            .foregroundStyle(.primary)

                        Text(car.model)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(.secondary)

                        HStack(spacing: 12) {
                            Label(car.plate, systemImage: "rectangle.fill")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(.tertiary)

                            Text("·")
                                .foregroundStyle(.tertiary)

                            Text(String(car.year))
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(.tertiary)
                        }
                    }

                    Spacer()

                    // Status + selection
                    VStack(alignment: .trailing, spacing: 8) {
                        StatusBadge(status: car.isConnected ? .connected : .disconnected)

                        if isSelected {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 20))
                                .foregroundStyle(accentColor)
                                .transition(.scale.combined(with: .opacity))
                        }
                    }
                }
            }
        }
        .buttonStyle(.plain)
        .overlay {
            if isSelected {
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .stroke(accentColor.opacity(0.4), lineWidth: 1.5)
            }
        }
    }
}

#Preview {
    ZStack {
        Color.white.ignoresSafeArea()
        VStack(spacing: 12) {
            CarRow(car: MockData.cars[0], isSelected: true)
            CarRow(car: MockData.cars[1], isSelected: false)
        }
        .padding()
    }
}
