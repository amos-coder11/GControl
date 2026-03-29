import SwiftUI

struct MetricCard: View {
    let label: String
    let value: String
    let unit: String
    let icon: String
    let color: Color
    let progress: Double

    init(
        label: String,
        value: String,
        unit: String,
        icon: String,
        color: Color = .cyan,
        progress: Double = 0.5
    ) {
        self.label = label
        self.value = value
        self.unit = unit
        self.icon = icon
        self.color = color
        self.progress = progress
    }

    var body: some View {
        GlassCard(cornerRadius: 18, padding: 14) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    Image(systemName: icon)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(color)

                    Text(label)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.secondary)
                }

                HStack(alignment: .firstTextBaseline, spacing: 3) {
                    Text(value)
                        .font(.system(size: 28, weight: .bold, design: .rounded))
                        .foregroundStyle(.primary)
                        .monospacedDigit()
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)

                    Text(unit)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.secondary)
                }

                // No GeometryReader here — it can confuse ScrollView width math and cause horizontal clipping.
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.primary.opacity(0.12))
                        .frame(maxWidth: .infinity)
                        .frame(height: 4)

                    Capsule()
                        .fill(
                            LinearGradient(
                                colors: [color.opacity(0.7), color],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(maxWidth: .infinity)
                        .frame(height: 4)
                        .scaleEffect(
                            x: CGFloat(min(max(progress, 0), 1)),
                            y: 1,
                            anchor: .leading
                        )
                }
                .frame(height: 4)
                .frame(maxWidth: .infinity)
            }
            .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
        }
    }
}

#Preview {
    ZStack {
        Color.white.ignoresSafeArea()
        MetricCard(
            label: "Velocidad",
            value: "72",
            unit: "km/h",
            icon: "gauge.with.dots.needle.50percent",
            color: .cyan,
            progress: 0.45
        )
        .frame(width: 170)
        .padding()
    }
}
