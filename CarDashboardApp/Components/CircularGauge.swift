import SwiftUI

struct CircularGauge: View {
    let value: Double
    let maxValue: Double
    let label: String
    let unit: String
    let color: Color
    var size: CGFloat = 200
    var lineWidth: CGFloat = 14

    private var progress: Double {
        guard maxValue > 0 else { return 0 }
        return min(value / maxValue, 1.0)
    }

    private var displayValue: String {
        String(format: "%.0f", value)
    }

    var body: some View {
        ZStack {
            // Background ring
            Circle()
                .stroke(
                    Color.primary.opacity(0.08),
                    style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
                )

            // Progress arc
            Circle()
                .trim(from: 0, to: progress)
                .stroke(
                    AngularGradient(
                        colors: [color.opacity(0.4), color, color.opacity(0.9)],
                        center: .center,
                        startAngle: .degrees(0),
                        endAngle: .degrees(360 * progress)
                    ),
                    style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
                .shadow(color: color.opacity(0.25), radius: 4, x: 0, y: 0)

            // Center content (avoid .contentTransition(.numericText) — it causes ghosted/overlapping digits during updates)
            VStack(spacing: 4) {
                Text(displayValue)
                    .font(.system(size: size * 0.28, weight: .bold, design: .rounded))
                    .foregroundStyle(.primary)
                    .monospacedDigit()
                    .lineLimit(1)

                Text(unit)
                    .font(.system(size: size * 0.08, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)

                Text(label)
                    .font(.system(size: size * 0.065, weight: .medium))
                    .foregroundStyle(.tertiary)
            }
        }
        .frame(width: size, height: size)
    }
}

#Preview {
    ZStack {
        Color.white.ignoresSafeArea()
        CircularGauge(
            value: 72,
            maxValue: 260,
            label: "Velocidad",
            unit: "km/h",
            color: .cyan
        )
    }
}
