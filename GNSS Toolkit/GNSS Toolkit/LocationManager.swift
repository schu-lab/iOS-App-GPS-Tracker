//
//  LocationManager.swift
//  GNSS Toolkit
//
//  Created by Simon Chu on 9/1/25.
//

import Foundation
import CoreLocation
import Combine

final class LocationManager: NSObject, ObservableObject, CLLocationManagerDelegate {
    private let manager = CLLocationManager()

    // Published telemetry (SI units internally: meters, m/s)
    @Published var latitude: Double?
    @Published var longitude: Double?
    @Published var altitudeMSL: Double?         // meters (CoreLocation altitude ~MSL)
    @Published var altitudeAGL: Double?         // meters (via Maff.AGL)
    @Published var speedInstantMS: Double?      // m/s
    @Published var speedAvg10sMS: Double?       // m/s (mean over last 10s)
    @Published var lastFix: Date?               // timestamp of last location

    // AGL reference: altitude MSL at "ground" (meters)
    private var aglReferenceMSL: Double?

    // 10-second rolling mean for speed
    private var speedAverager = Maff.RollingMeanWindow(windowSeconds: 10)

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBest
        manager.distanceFilter = kCLDistanceFilterNone
        manager.activityType = .other
        manager.pausesLocationUpdatesAutomatically = true
    }

    func start() {
        manager.requestWhenInUseAuthorization()
        if CLLocationManager.locationServicesEnabled() {
            manager.startUpdatingLocation()
        }
    }

    func stop() {
        manager.stopUpdatingLocation()
        speedAverager.reset()
    }

    /// Re-baseline AGL to the current altitude (or clear if none yet).
    func resetAGLToCurrentAltitude() {
        altitudeAGL = Maff.AGL.reset(refMSL: &aglReferenceMSL, to: altitudeMSL)
    }

    // MARK: - CLLocationManagerDelegate
    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        switch manager.authorizationStatus {
        case .authorizedAlways, .authorizedWhenInUse:
            manager.startUpdatingLocation()
        case .denied, .restricted:
            manager.stopUpdatingLocation()
        case .notDetermined:
            break
        @unknown default:
            break
        }
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        print("Location error: \(error)")
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let loc = locations.last else { return }
        guard loc.horizontalAccuracy >= 0 else { return } // ignore invalid fixes

        let coord = loc.coordinate

        DispatchQueue.main.async {
            self.latitude   = coord.latitude
            self.longitude  = coord.longitude
            self.altitudeMSL = loc.altitude
            self.lastFix    = loc.timestamp

            // AGL via Maff (lazy baseline)
            self.altitudeAGL = Maff.AGL.compute(currentMSL: self.altitudeMSL,
                                                refMSL: &self.aglReferenceMSL)

            // Speed: CoreLocation uses negative speed when invalid; treat as 0 for averaging
            if loc.speed >= 0 {
                self.speedInstantMS = loc.speed
                self.speedAverager.add(value: loc.speed, at: loc.timestamp)
            } else {
                self.speedInstantMS = nil
                self.speedAverager.add(value: 0, at: loc.timestamp)
            }
            self.speedAvg10sMS = self.speedAverager.mean
        }
    }
}
