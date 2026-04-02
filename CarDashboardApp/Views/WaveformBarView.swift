import SwiftUI

/// Single vertical bar; grows from the vertical center (Telegram / ChatGPT style).
struct WaveformBarView: View {
    var amplitude: CGFloat
    var maxHeight: CGFloat
    var barWidth: CGFloat
    var cornerRadius: CGFloat
    var color: Color

    private static let minimumRenderedHeight: CGFloat = 4

    var body: some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(color)
            .frame(width: barWidth, height: max(Self.minimumRenderedHeight, amplitude * maxHeight))
            .frame(maxHeight: maxHeight, alignment: .center)
    }
}
