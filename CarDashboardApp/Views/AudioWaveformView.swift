import SwiftUI

struct AudioWaveformView: View {
    @ObservedObject var monitor: AudioWaveformMonitor
    var barColor: Color
    var barWidth: CGFloat
    var spacing: CGFloat
    /// Altura fija del área de barras (evita que `GeometryReader` crezca y devore el layout).
    var layoutHeight: CGFloat
    /// Reparte el ancho entre todas las barras (esquina a esquina en la cápsula).
    var fillsAvailableWidth: Bool

    init(
        monitor: AudioWaveformMonitor,
        barColor: Color = .blue,
        barWidth: CGFloat = 3,
        spacing: CGFloat = 3,
        layoutHeight: CGFloat = 60,
        fillsAvailableWidth: Bool = false
    ) {
        self.monitor = monitor
        self.barColor = barColor
        self.barWidth = barWidth
        self.spacing = spacing
        self.layoutHeight = layoutHeight
        self.fillsAvailableWidth = fillsAvailableWidth
    }

    var body: some View {
        GeometryReader { geometry in
            let levels = monitor.amplitudeLevels
            let count = levels.count
            let (barW, gap): (CGFloat, CGFloat) = {
                guard fillsAvailableWidth, count > 0 else {
                    return (barWidth, spacing)
                }
                let g = spacing
                let totalGaps = CGFloat(max(0, count - 1)) * g
                let w = max(0.5, (geometry.size.width - totalGaps) / CGFloat(count))
                return (w, g)
            }()
            HStack(alignment: .center, spacing: gap) {
                ForEach(Array(levels.enumerated()), id: \.offset) { _, level in
                    WaveformBarView(
                        amplitude: CGFloat(level),
                        maxHeight: geometry.size.height,
                        barWidth: barW,
                        cornerRadius: min(2, barW * 0.45),
                        color: barColorForState(amplitude: level)
                    )
                }
            }
            .frame(width: geometry.size.width, height: geometry.size.height, alignment: .center)
        }
        .frame(height: layoutHeight)
    }

    private func barColorForState(amplitude: Float) -> Color {
        if monitor.lastError != nil {
            return Color.red.opacity(0.6)
        }
        if monitor.isListening {
            if amplitude > 0.15 {
                return barColor
            }
            return barColor.opacity(0.7)
        }
        return Color.gray.opacity(0.5)
    }
}
