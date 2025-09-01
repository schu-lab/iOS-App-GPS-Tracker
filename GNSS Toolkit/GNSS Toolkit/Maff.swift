//
//  Maff.swift
//  GNSS Toolkit
//
//  Created by Simon Chu on 9/1/25.
//

import Foundation

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
        /// Compute AGL and lazily initialize the reference to the current MSL if needed.
        static func compute(currentMSL: Double?, refMSL: inout Double?) -> Double? {
            guard let m = currentMSL else { return nil }
            if refMSL == nil {
                refMSL = m
                return 0
            }
            return m - (refMSL ?? m)
        }
        
        /// Reset the AGL reference to the provided current MSL.
        /// Returns 0 if currentMSL exists, otherwise nil.
        static func reset(refMSL: inout Double?, to currentMSL: Double?) -> Double? {
            refMSL = currentMSL
            return currentMSL == nil ? nil : 0
        }
        
        /// Clear AGL reference so the next compute() re-baselines automatically.
        static func clear(refMSL: inout Double?) {
            refMSL = nil
        }
    }
    
    // MARK: - Rolling mean over a time window
    /// Maintains a simple rolling mean over the last `windowSeconds`.
    struct RollingMeanWindow {
        private let window: TimeInterval
        private var samples: [(time: Date, value: Double)] = []
        
        init(windowSeconds: TimeInterval) {
            self.window = windowSeconds
        }
        
        /// Add a new sample and drop any older than the window.
        mutating func add(value: Double, at time: Date = Date()) {
            samples.append((time, value))
            prune(now: time)
        }
        
        /// Current mean (simple average of kept samples). Returns nil if empty.
        var mean: Double? {
            guard !samples.isEmpty else { return nil }
            let sum = samples.reduce(0) { $0 + $1.value }
            return sum / Double(samples.count)
        }
        
        /// Remove samples older than `now - window`.
        private mutating func prune(now: Date = Date()) {
            let cutoff = now.addingTimeInterval(-window)
            samples.removeAll { $0.time < cutoff }
        }
        
        /// Reset all samples.
        mutating func reset() {
            samples.removeAll(keepingCapacity: false)
        }
    }
    
    // MARK: - Time
    enum TimeMode: String, CaseIterable {
        case utc = "UTC"
        case local = "Local"
    }
    
    /// Friendly timestamp (UTC or Local).
    /// Examples:
    ///  - UTC:   "2025-09-01 14:07:01 UTC"
    ///  - Local: "2025-09-01 07:07:01 PDT"
    static func timeText(date: Date?, mode: TimeMode) -> String {
        guard let date else { return "--" }
        
        switch mode {
        case .utc:
            // Force literal "UTC" regardless of the system's abbreviation for GMT+0
            let df = DateFormatter()
            df.locale = Locale(identifier: "en_US_POSIX")
            df.timeZone = TimeZone(secondsFromGMT: 0)
            df.dateFormat = "yyyy-MM-dd HH:mm:ss 'UTC'"
            return df.string(from: date)
            
        case .local:
            // Use the local zone’s abbreviation (PDT, PST, etc.)
            let df = DateFormatter()
            df.locale = Locale(identifier: "en_US_POSIX")
            df.timeZone = .current
            df.dateFormat = "yyyy-MM-dd HH:mm:ss z"
            return df.string(from: date)
        }
    }
}
