import SwiftUI

/// Standalone demo: black canvas, waveform, start/stop (uses internal `AVAudioEngine`).
struct WaveformDemoView: View {
    @StateObject private var monitor = AudioWaveformMonitor()

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VStack(spacing: 24) {
                AudioWaveformView(monitor: monitor, barColor: .white, barWidth: 3, spacing: 3)
                    .frame(height: 60)
                    .padding(.horizontal, 20)

                Button {
                    Task {
                        if monitor.isListening {
                            monitor.stopMonitoring()
                        } else {
                            await monitor.startMonitoring()
                        }
                    }
                } label: {
                    Text(monitor.isListening ? "Stop" : "Start Listening")
                        .font(.headline)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 24)
                        .padding(.vertical, 12)
                        .background(Capsule().fill(Color.blue.opacity(0.85)))
                }

                if let err = monitor.lastError {
                    Text(err.localizedDescription)
                        .font(.footnote)
                        .foregroundStyle(.red)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                }
            }
        }
    }
}

#Preview("Waveform demo") {
    WaveformDemoView()
}
