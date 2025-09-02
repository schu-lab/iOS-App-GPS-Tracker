//  MapTracker.swift
//  GNSS Toolkit
//
//  Based on your TrackingScreen baseline, adapted to this project:
//  - Uses existing LocationManager (optional fields & lastFix)
//  - Compact HUD: Distance · Avg · Speed · Time (elapsed)
//  - Controls: Start/Stop, Reset, Export GPX, Recenter
//  - Rounded inset map with bold route line
//  - Optional overlays (Origin / Target / Geofence) via @AppStorage
//
//  Keys for overlays (set elsewhere, e.g. from MapManager):
//    "overlay_origin"  -> "lat,lon"
//    "overlay_target"  -> "lat,lon"
//    "overlay_fence_m" -> Double radius meters (0 = none)

import SwiftUI
import MapKit
import CoreLocation
import UniformTypeIdentifiers

struct MapTracker: View {
    @ObservedObject var lm: LocationManager

    // Display prefs
    @AppStorage("useFeet") private var useFeet = false

    // Map state
    @State private var camera: MapCameraPosition = .userLocation(fallback: .automatic)
    @State private var didInitialCenter = false

    // Session state
    @State private var isRecording = false
    @State private var points: [TrackPoint] = []
    @State private var distanceMeters: CLLocationDistance = 0
    @State private var startTime: Date?
    @State private var elapsed: TimeInterval = 0
    @State private var maxSpeedMps: Double = 0

    @State private var lastCoord: CLLocationCoordinate2D?
    @State private var lastTimestamp: Date?

    // Export
    @State private var shareURL: URL?
    @State private var showShare = false

    // Ticker for elapsed
    private let ticker = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    // Optional overlays (Origin/Target/Geofence)
    @AppStorage("overlay_origin") private var overlayOriginString: String = ""  // "lat,lon"
    @AppStorage("overlay_target") private var overlayTargetString: String = ""  // "lat,lon"
    @AppStorage("overlay_fence_m") private var overlayFenceMeters: Double = 0   // meters

    var body: some View {
        VStack(spacing: 12) {
            // Map (rounded inset)
            Map(position: $camera, interactionModes: .all) {
                // Live user annotation
                UserAnnotation()

                // Route line
                if coordinates.count >= 2 {
                    MapPolyline(coordinates: coordinates)
                        .stroke(.blue, lineWidth: 5)
                }

                // Overlays: Origin / Target
                if let o = parseLatLon(overlayOriginString) {
                    Annotation("Origin", coordinate: o) {
                        Image(systemName: "triangle.fill")
                            .rotationEffect(.degrees(180))
                            .foregroundStyle(.blue)
                            .shadow(radius: 2)
                    }
                }
                if let t = parseLatLon(overlayTargetString) {
                    Annotation("Target", coordinate: t) {
                        Image(systemName: "triangle.fill")
                            .rotationEffect(.degrees(180))
                            .foregroundStyle(.red)
                            .shadow(radius: 2)
                    }
                }
                // Geofence (outline only)
                if let o = parseLatLon(overlayOriginString), overlayFenceMeters > 0 {
                    MapCircle(center: o, radius: overlayFenceMeters)
                        .stroke(.red, lineWidth: 2)
                        .foregroundStyle(.clear)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(.secondary.opacity(0.25), lineWidth: 0.5))
            .padding(.horizontal, 12)
            .padding(.top, 6)
            .onMapCameraChange { _ in
                if !didInitialCenter, let c = currentCoordinate {
                    didInitialCenter = true
                    let span = MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01)
                    camera = .region(MKCoordinateRegion(center: c, span: span))
                }
            }

            // HUD (compact row)
            VStack(spacing: 6) {
                HStack {
                    stat("Distance", Maff.distanceText(fromMeters: distanceMeters, useFeet: useFeet))
                    Spacer(minLength: 8)
                    stat("Avg",      speedPretty(averageSpeedMps))
                    Spacer(minLength: 8)
                    stat("Speed",    speedPretty(currentSpeedMps))
                    Spacer(minLength: 8)
                    stat("Time",     timeString(elapsed))
                }
                .mono10()
                .monospacedDigit()
            }
            .padding(10)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(.secondary.opacity(0.25), lineWidth: 0.5))
            .padding(.horizontal, 12)

            // Controls
            HStack(spacing: 10) {
                Button(isRecording ? "Stop" : "Start") {
                    isRecording ? stopRecording() : startRecording()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .tint(isRecording ? .red : .blue)

                Button("Reset") { resetSession() }
                    .buttonStyle(.bordered)
                    .controlSize(.small)

                Button("Export GPX") { exportGpx() }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .disabled(points.count < 2)

                Spacer(minLength: 8)

                Button {
                    if let c = currentCoordinate {
                        withAnimation(.easeInOut) {
                            camera = .region(MKCoordinateRegion(center: c,
                                                                span: MKCoordinateSpan(latitudeDelta: 0.004, longitudeDelta: 0.004)))
                        }
                    }
                } label: {
                    Label("Recenter", systemImage: "location.north.line")
                        .labelStyle(.titleAndIcon)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
            .mono10()
            .padding(.horizontal, 12)
            .padding(.bottom, 8)
        }
        .padding(.bottom, 2)
        .environment(\.font, AppTheme.baseFont)
        // Use your LM’s optional lastFix to tick updates (instead of lastFixDate)
        .onChange(of: lm.lastFix) { _ in onNewLocationFix() }
        .onReceive(ticker) { _ in
            guard isRecording, let start = startTime else { return }
            elapsed = Date().timeIntervalSince(start)
        }
        .onAppear {
            // ContentView already starts LM at the top level. :contentReference[oaicite:4]{index=4}
            if let c = currentCoordinate, !didInitialCenter {
                camera = .region(MKCoordinateRegion(center: c,
                                                    span: MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01)))
                didInitialCenter = true
            }
        }
    }

    // MARK: - Derived

    private var currentCoordinate: CLLocationCoordinate2D? {
        guard let lat = lm.latitude, let lon = lm.longitude else { return nil }
        return CLLocationCoordinate2D(latitude: lat, longitude: lon)
    }

    private var coordinates: [CLLocationCoordinate2D] {
        points.map { $0.coordinate }
    }

    private var averageSpeedMps: Double {
        guard elapsed > 0 else { return 0 }
        return distanceMeters / elapsed
    }

    private var currentSpeedMps: Double {
        guard
            let lastT = lastTimestamp,
            let lastC = lastCoord,
            let newC = currentCoordinate,
            let newT = lm.lastFix
        else { return 0 }
        let dt = newT.timeIntervalSince(lastT)
        guard dt > 0.1 else { return 0 }
        let d = CLLocation(latitude: lastC.latitude, longitude: lastC.longitude)
            .distance(from: CLLocation(latitude: newC.latitude, longitude: newC.longitude))
        return d / dt
    }

    // MARK: - Actions

    private func startRecording() {
        resetSession()
        isRecording = true
        startTime = Date()
        if let c = currentCoordinate {
            appendPoint(at: c, time: lm.lastFix ?? Date())
        }
    }

    private func stopRecording() {
        isRecording = false
        // (Optional) persist a session here if/when you add a TrackStore
    }

    private func resetSession() {
        isRecording = false
        points.removeAll()
        distanceMeters = 0
        elapsed = 0
        startTime = nil
        maxSpeedMps = 0
        lastCoord = nil
        lastTimestamp = nil
    }

    private func onNewLocationFix() {
        guard isRecording, let newC = currentCoordinate else { return }
        let now = lm.lastFix ?? Date()

        if let lastC = lastCoord, let lastT = lastTimestamp {
            let d = CLLocation(latitude: lastC.latitude, longitude: lastC.longitude)
                .distance(from: CLLocation(latitude: newC.latitude, longitude: newC.longitude))

            if d >= 1.0 {
                distanceMeters += d
                let dt = now.timeIntervalSince(lastT)
                if dt > 0.1 {
                    let v = d / dt
                    maxSpeedMps = max(maxSpeedMps, v)
                }
                appendPoint(at: newC, time: now)
            }
        } else {
            appendPoint(at: newC, time: now)
        }
    }

    private func appendPoint(at coord: CLLocationCoordinate2D, time: Date) {
        let alt = lm.altitudeMSL ?? 0
        let tp = TrackPoint(coordinate: coord, altitudeMSL: alt, timestamp: time)
        points.append(tp)
        lastCoord = coord
        lastTimestamp = time
    }

    // MARK: - Export

    private func exportGpx() {
        guard points.count >= 2 else { return }
        let gpx = buildGpx(points: points)
        let filename = "Track-\(DateFormatter.gpxTimestamp.string(from: Date())).gpx"
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(filename)

        do {
            try gpx.write(to: url, atomically: true, encoding: .utf8)
            shareURL = url
            showShare = true
        } catch {
            print("Failed to write GPX: \(error)")
        }
    }

    private func buildGpx(points: [TrackPoint]) -> String {
        let header = """
        <?xml version="1.0" encoding="UTF-8"?>
        <gpx version="1.1" creator="GNSS Toolkit" xmlns="http://www.topografix.com/GPX/1/1">
          <trk>
            <name>Track \(DateFormatter.gpxTimestamp.string(from: startTime ?? Date()))</name>
            <trkseg>
        """
        let footer = """
            </trkseg>
          </trk>
        </gpx>
        """

        let iso = ISO8601DateFormatter()
        iso.timeZone = TimeZone(secondsFromGMT: 0)
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

        let body = points.map { p in
            """
              <trkpt lat="\(p.latitude)" lon="\(p.longitude)">
                <ele>\(String(format: "%.2f", p.altitudeMSL))</ele>
                <time>\(iso.string(from: p.timestamp))</time>
              </trkpt>
            """
        }.joined(separator: "\n")

        return [header, body, footer].joined(separator: "\n")
    }

    // MARK: - UI helpers

    private func stat(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).foregroundStyle(.secondary)
            Text(value)
        }
    }

    private func speedPretty(_ mps: Double) -> String {
        if useFeet {
            let mph = mps * 2.2369362921
            return String(format: "%.1f mph", mph)
        } else {
            let kph = mps * 3.6
            return String(format: "%.1f km/h", kph)
        }
    }

    private func parseLatLon(_ s: String) -> CLLocationCoordinate2D? {
        let parts = s.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
        guard parts.count == 2, let lat = Double(parts[0]), let lon = Double(parts[1]), abs(lat) <= 90, abs(lon) <= 180 else {
            return nil
        }
        return .init(latitude: lat, longitude: lon)
    }

    private func timeString(_ t: TimeInterval) -> String {
        guard t > 0 else { return "00:00:00" }
        let h = Int(t) / 3600
        let m = (Int(t) % 3600) / 60
        let s = Int(t) % 60
        return String(format: "%02d:%02d:%02d", h, m, s)
    }
}

// MARK: - Models reused from your baseline

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

private extension DateFormatter {
    static let gpxTimestamp: DateFormatter = {
        let f = DateFormatter()
        f.timeZone = TimeZone(secondsFromGMT: 0)
        f.dateFormat = "yyyyMMdd-HHmmss"
        return f
    }()
}
