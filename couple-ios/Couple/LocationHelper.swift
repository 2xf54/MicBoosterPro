import Foundation
import CoreLocation

final class LocationHelper: NSObject, ObservableObject, CLLocationManagerDelegate {
    private let manager = CLLocationManager()
    @Published var statusText: String = ""
    private var onLocation: ((CLLocationCoordinate2D) -> Void)?

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyKilometer
    }

    func requestCurrentLocation(completion: @escaping (CLLocationCoordinate2D) -> Void) {
        onLocation = completion
        statusText = "Locating..."
        let auth = manager.authorizationStatus
        if auth == .notDetermined {
            manager.requestWhenInUseAuthorization()
        } else if auth == .authorizedWhenInUse || auth == .authorizedAlways {
            manager.requestLocation()
        } else {
            statusText = "Location permission denied in Settings"
        }
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let auth = manager.authorizationStatus
        if auth == .authorizedWhenInUse || auth == .authorizedAlways {
            if onLocation != nil {
                manager.requestLocation()
            }
        } else if auth == .denied || auth == .restricted {
            statusText = "Location permission denied"
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let loc = locations.first else { return }
        DispatchQueue.main.async {
            self.statusText = String(format: "%.2f, %.2f", loc.coordinate.latitude, loc.coordinate.longitude)
            self.onLocation?(loc.coordinate)
            self.onLocation = nil
        }
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        DispatchQueue.main.async {
            self.statusText = "Could not get location"
            self.onLocation = nil
        }
    }
}
