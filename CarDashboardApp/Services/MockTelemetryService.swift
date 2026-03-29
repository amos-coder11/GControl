import Foundation

final class MockTelemetryService: TelemetryService {
    private var baseSpeed: Double = 72
    private var baseRPM: Double = 2800
    private var baseTemp: Double = 88
    private var baseFuel: Double = 68
    private var baseBattery: Double = 92
    private var baseTurbo: Double = 1.2

    func fetchSpeed() -> Double {
        fluctuate(base: baseSpeed, range: 8, min: 0, max: 260)
    }

    func fetchRPM() -> Double {
        fluctuate(base: baseRPM, range: 400, min: 800, max: 8000)
    }

    func fetchTemperature() -> Double {
        fluctuate(base: baseTemp, range: 3, min: 60, max: 130)
    }

    func fetchFuel() -> Double {
        fluctuate(base: baseFuel, range: 0.5, min: 0, max: 100)
    }

    func fetchBattery() -> Double {
        fluctuate(base: baseBattery, range: 0.3, min: 0, max: 100)
    }

    func fetchTurbo() -> Double {
        fluctuate(base: baseTurbo, range: 0.15, min: 0, max: 2.5)
    }

    private func fluctuate(base: Double, range: Double, min: Double, max: Double) -> Double {
        let delta = Double.random(in: -range...range)
        return Swift.min(Swift.max(base + delta, min), max)
    }
}
