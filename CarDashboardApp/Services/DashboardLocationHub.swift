import Combine
import CoreLocation
import Foundation

/// Permisos + posición para el mapa de Inicio y envío a Supabase.
@MainActor
final class DashboardLocationHub: NSObject, ObservableObject {
    @Published private(set) var authorizationStatus: CLAuthorizationStatus
    @Published private(set) var coordinate: CLLocationCoordinate2D?

    private let manager = CLLocationManager()
    private var lastPushed: CLLocationCoordinate2D?
    private var lastPushTime: Date?

    var onLocationForUpload: ((CLLocationCoordinate2D) -> Void)?

    override init() {
        authorizationStatus = manager.authorizationStatus
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
    }

    func requestWhenInUseAndStart() {
        manager.requestWhenInUseAuthorization()
        manager.startUpdatingLocation()
    }

    func stopUpdates() {
        manager.stopUpdatingLocation()
    }

    private func considerUpload(_ c: CLLocationCoordinate2D) {
        guard CLLocationCoordinate2DIsValid(c) else { return }
        let now = Date()
        if let t = lastPushTime, now.timeIntervalSince(t) < 25 { return }
        if let p = lastPushed {
            let a = CLLocation(latitude: p.latitude, longitude: p.longitude)
            let b = CLLocation(latitude: c.latitude, longitude: c.longitude)
            if a.distance(from: b) < 40 { return }
        }
        lastPushed = c
        lastPushTime = now
        onLocationForUpload?(c)
    }
}

extension DashboardLocationHub: CLLocationManagerDelegate {
    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        Task { @MainActor in
            self.authorizationStatus = manager.authorizationStatus
            if self.authorizationStatus == .authorizedWhenInUse || self.authorizationStatus == .authorizedAlways {
                manager.startUpdatingLocation()
            }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let loc = locations.last else { return }
        let c = loc.coordinate
        Task { @MainActor in
            self.coordinate = c
            self.considerUpload(c)
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        _ = error
    }
}
