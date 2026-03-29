import Foundation

protocol TelemetryService {
    func fetchSpeed() -> Double
    func fetchRPM() -> Double
    func fetchTemperature() -> Double
    func fetchFuel() -> Double
    func fetchBattery() -> Double
    func fetchTurbo() -> Double
}
