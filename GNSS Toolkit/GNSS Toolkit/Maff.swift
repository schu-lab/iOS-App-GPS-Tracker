//  Maff.swift
//  GNSS Toolkit

import Foundation
import SwiftUI        // for ShareSheetView
import UIKit          // for UIActivityViewController
import CoreLocation   // for CLLocationCoordinate2D

enum Maff {
    // MARK: - Constants
    static let feetPerMeter: Double = 3.28083989501312
    
    // MARK: - Distance (meters <-> feet)
    static func distance(_ meters: Double, useFeet: Bool) -> (value: Double, unit: String) {
        useFeet ? (meters * feetPerMeter, "ft") : (meters, "m")
    }
    
    static func distanceText(fromMeters meters: Double?, useFeet: Bool, decimals: Int = 2) -> String {
        guard let meters else { return "--" }
        let (v, unit) = distance(meters, useFeet: useFeet)
        return String(format: "%.\(decimals)f %@", v, unit)
    }
    
    // MARK: - Speed (m/s <-> ft/s)
    static func speedMS(_ ms: Double, useFeet: Bool) -> (value: Double, unit: String) {
        useFeet ? (ms * feetPerMeter, "ft/s") : (ms, "m/s")
    }
    
    static func speedText(fromMS ms: Double?, useFeet: Bool, decimals: Int = 2) -> String {
        guard let ms else { return "--" }
        let (v, unit) = speedMS(ms, useFeet: useFeet)
        return String(format: "%.\(decimals)f %@", v, unit)
    }
    
    // MARK: - Coordinates
    static func coordsText(lat: Double?, lon: Double?, decimals: Int = 6) -> String {
        guard let lat, let lon else { return "--" }
        return String(format: "%.\(decimals)f, %.\(decimals)f", lat, lon)
    }
    
    // MARK: - AGL helpers
    enum AGL {
        static func compute(currentMSL: Double?, refMSL: inout Double?) -> Double? {
            guard let m = currentMSL else { return nil }
            if refMSL == nil {
                refMSL = m
                return 0
            }
            return m - (refMSL ?? m)
        }
        
        static func reset(refMSL: inout Double?, to currentMSL: Double?) -> Double? {
            refMSL = currentMSL
            return currentMSL == nil ? nil : 0
        }
        
        static func clear(refMSL: inout Double?) {
            refMSL = nil
        }
    }
    
    // MARK: - Rolling mean
    struct RollingMeanWindow {
        private let window: TimeInterval
        private var samples: [(time: Date, value: Double)] = []
        
        init(windowSeconds: TimeInterval) {
            self.window = windowSeconds
        }
        
        mutating func add(value: Double, at time: Date = Date()) {
            samples.append((time, value))
            prune(now: time)
        }
        
        var mean: Double? {
            guard !samples.isEmpty else { return nil }
            let sum = samples.reduce(0) { $0 + $1.value }
            return sum / Double(samples.count)
        }
        
        private mutating func prune(now: Date = Date()) {
            let cutoff = now.addingTimeInterval(-window)
            samples.removeAll { $0.time < cutoff }
        }
        
        mutating func reset() {
            samples.removeAll(keepingCapacity: false)
        }
    }
    
    // MARK: - Time
    enum TimeMode: String, CaseIterable {
        case utc = "UTC"
        case local = "Local"
    }
    
    static func timeText(date: Date?, mode: TimeMode) -> String {
        guard let date else { return "--" }
        switch mode {
        case .utc:
            let df = DateFormatter()
            df.locale = Locale(identifier: "en_US_POSIX")
            df.timeZone = TimeZone(secondsFromGMT: 0)
            df.dateFormat = "yyyy-MM-dd HH:mm:ss 'UTC'"
            return df.string(from: date)
        case .local:
            let df = DateFormatter()
            df.locale = Locale(identifier: "en_US_POSIX")
            df.timeZone = .current
            df.dateFormat = "yyyy-MM-dd HH:mm:ss z"
            return df.string(from: date)
        }
    }
    
    // MARK: - Tracker/Map shared helpers
    static func hms(from seconds: TimeInterval?) -> String {
        guard let t = seconds, t > 0 else { return "00:00:00" }
        let h = Int(t) / 3600
        let m = (Int(t) % 3600) / 60
        let s = Int(t) % 60
        return String(format: "%02d:%02d:%02d", h, m, s)
    }

    static func speedPrettyText(fromMps mps: Double, useFeet: Bool) -> String {
        if useFeet {
            let mph = mps * 2.2369362921
            return String(format: "%.1f mph", mph)
        } else {
            let kph = mps * 3.6
            return String(format: "%.1f km/h", kph)
        }
    }

    static func parseLatLon(_ s: String) -> (lat: Double, lon: Double)? {
        let parts = s.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
        guard parts.count == 2, let lat = Double(parts[0]), let lon = Double(parts[1]),
              abs(lat) <= 90, abs(lon) <= 180 else { return nil }
        return (lat, lon)
    }

    enum DateFormats {
        static let gpxFileStamp: DateFormatter = {
            let f = DateFormatter()
            f.timeZone = TimeZone(secondsFromGMT: 0)
            f.dateFormat = "yyyyMMdd-HHmmss"
            return f
        }()
    }
}

// MARK: - Shared models & views (moved here for single-source-of-truth)

public struct TrackPoint: Identifiable, Codable {
    public let id: UUID
    public let latitude: Double
    public let longitude: Double
    public let altitudeMSL: Double
    public let timestamp: Date

    public init(
        id: UUID = UUID(),
        coordinate: CLLocationCoordinate2D,
        altitudeMSL: Double,
        timestamp: Date
    ) {
        self.id = id
        self.latitude = coordinate.latitude
        self.longitude = coordinate.longitude
        self.altitudeMSL = altitudeMSL
        self.timestamp = timestamp
    }

    public var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }
}

/// Reusable share sheet wrapper
public struct ShareSheetView: UIViewControllerRepresentable {
    public let url: URL
    public var onDismiss: (() -> Void)? = nil

    public init(url: URL, onDismiss: (() -> Void)? = nil) {
        self.url = url
        self.onDismiss = onDismiss
    }

    public func makeUIViewController(context: Context) -> UIActivityViewController {
        let vc = UIActivityViewController(activityItems: [url], applicationActivities: nil)
        vc.completionWithItemsHandler = { _, _, _, _ in onDismiss?() }
        return vc
    }

    public func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
