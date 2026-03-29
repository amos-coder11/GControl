import Foundation
import SwiftUI
import Combine

@MainActor
final class DashboardViewModel: ObservableObject {
    @Published var speed: Double = 72
    @Published var rpm: Double = 2800
    @Published var temperature: Double = 88
    @Published var fuel: Double = 68
    @Published var battery: Double = 92
    @Published var turbo: Double = 1.2
    @Published var status: CarStatus = .connected
    @Published var isLive: Bool = true

    private let telemetry: TelemetryService
    private var timer: Timer?

    init(telemetry: TelemetryService = MockTelemetryService()) {
        self.telemetry = telemetry
        startUpdating()
    }

    func startUpdating() {
        timer?.invalidate()
        isLive = true
        timer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.updateMetrics()
            }
        }
    }

    func stopUpdating() {
        timer?.invalidate()
        timer = nil
        isLive = false
    }

    private func updateMetrics() {
        withAnimation(.easeInOut(duration: 0.8)) {
            speed = telemetry.fetchSpeed()
            rpm = telemetry.fetchRPM()
            temperature = telemetry.fetchTemperature()
            fuel = telemetry.fetchFuel()
            battery = telemetry.fetchBattery()
            turbo = telemetry.fetchTurbo()
        }
    }

    var speedText: String {
        String(format: "%.0f", speed)
    }

    var rpmText: String {
        String(format: "%.0f", rpm)
    }

    var temperatureText: String {
        String(format: "%.0f", temperature)
    }

    var fuelText: String {
        String(format: "%.0f", fuel)
    }

    var batteryText: String {
        String(format: "%.0f", battery)
    }

    var turboText: String {
        String(format: "%.1f", turbo)
    }

    deinit {
        timer?.invalidate()
    }
}
