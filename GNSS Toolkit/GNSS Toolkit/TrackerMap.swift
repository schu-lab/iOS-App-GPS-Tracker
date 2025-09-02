//  TrackerMap.swift
//  GNSS Toolkit

import SwiftUI
import MapKit
import CoreLocation

struct TrackerMap: View {
    @ObservedObject var lm: LocationManager
    @AppStorage("useFeet") private var useFeet = false

    @State private var camera: MapCameraPosition = .userLocation(fallback: .automatic)
    @State private var didInitialCenter = false

    @State private var isRecording = false
    @State private var points: [TrackPoint] = []
    @State private var distanceMeters: CLLocationDistance = 0
    @State private var startTime: Date?
    @State private var elapsed: TimeInterval = 0
    @State private var maxSpeedMps: Double = 0

    @State private var lastCoord: CLLocationCoordinate2D?
    @State private var lastTimestamp: Date?

    @State private var shareURL: URL?
    @State private var showShare = false

    private let ticker = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    @AppStorage("overlay_origin") private var overlayOriginString: String = ""
    @AppStorage("overlay_target") private var overlayTargetString: String = ""
    @AppStorage("overlay_fence_m") private var overlayFenceMeters: Double = 0

    var body: some View {
        ZStack {
            VStack(spacing: 12) {
                Map(position: $camera, interactionModes: .all) {
                    UserAnnotation()

                    if coordinates.count >= 2 {
                        MapPolyline(coordinates: coordinates)
                            .stroke(.blue, lineWidth: 5)
                    }

                    if let o = originCoord {
                        Annotation("Origin", coordinate: o) {
                            Image(systemName: "triangle.fill")
                                .rotationEffect(.degrees(180))
                                .foregroundStyle(.blue)
                        }
                    }
                    if let t = targetCoord {
                        Annotation("Target", coordinate: t) {
                            Image(systemName: "triangle.fill")
                                .rotationEffect(.degrees(180))
                                .foregroundStyle(.red)
                        }
                    }

                    if let line = originToTargetPolyline {
                        MapPolyline(line).stroke(.orange, lineWidth: 2)
                    }

                    if let o = originCoord, overlayFenceMeters > 0 {
                        MapCircle(center: o, radius: overlayFenceMeters)
                            .stroke(.red, lineWidth: 2)
                            .foregroundStyle(.clear)
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 18))
                .overlay(RoundedRectangle(cornerRadius: 18).stroke(.secondary.opacity(0.25)))
                .padding(.horizontal, 12)
                .padding(.top, 6)
                .onMapCameraChange { _ in
                    if !didInitialCenter, let c = currentCoordinate {
                        didInitialCenter = true
                        camera = .region(MKCoordinateRegion(center: c,
                                                            span: .init(latitudeDelta: 0.01, longitudeDelta: 0.01)))
                    }
                }

                // HUD
                VStack(spacing: 6) {
                    HStack {
                        stat("Distance", Maff.distanceText(fromMeters: distanceMeters, useFeet: useFeet))
                        Spacer(minLength: 8)
                        stat("Avg",   Maff.speedPrettyText(fromMps: averageSpeedMps, useFeet: useFeet))
                        Spacer(minLength: 8)
                        stat("Speed", Maff.speedPrettyText(fromMps: currentSpeedMps, useFeet: useFeet))
                        Spacer(minLength: 8)
                        stat("Time",  Maff.hms(from: elapsed))
                    }
                    .monospacedDigit()

                    HStack {
                        stat("MSL", Maff.distanceText(fromMeters: lm.altitudeMSL, useFeet: useFeet))
                        Spacer(minLength: 8)
                        stat("AGL", Maff.distanceText(fromMeters: lm.altitudeAGL, useFeet: useFeet))
                        Spacer()
                    }
                    .monospacedDigit()
                }
                .padding(10)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14))
                .overlay(RoundedRectangle(cornerRadius: 14).stroke(.secondary.opacity(0.25)))
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
                                                                    span: .init(latitudeDelta: 0.004, longitudeDelta: 0.004)))
                            }
                        }
                    } label: { Label("Recenter", systemImage: "location.north.line") }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
                .padding(.horizontal, 12)
                .padding(.bottom, 8)
            }

            // Title bar
            VStack {
                HStack(spacing: 8) {
                    Image("Icon-DEV")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 22, height: 22)
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                        .overlay(RoundedRectangle(cornerRadius: 4).stroke(.secondary.opacity(0.3)))

                    Text("Tracker Map").monoTitle()
                    Spacer()
                }
                .padding(.horizontal, 12)
                .padding(.top, 8)

                Spacer()
            }
        }
        .padding(.bottom, 2)
        .environment(\.font, AppTheme.baseFont)
        .onChange(of: lm.lastFix) { _ in onNewLocationFix() }
        .onReceive(ticker) { _ in
            guard isRecording, let start = startTime else { return }
            elapsed = Date().timeIntervalSince(start)
        }
        .sheet(isPresented: $showShare) {        // uses the shared one from Maff.swift
            if let url = shareURL {
                ShareSheetView(url: url) { removeTemp(url) }
            }
        }
    }

    // MARK: - Derived / actions (unchanged from your version)
    private var currentCoordinate: CLLocationCoordinate2D? {
        guard let lat = lm.latitude, let lon = lm.longitude else { return nil }
        return CLLocationCoordinate2D(latitude: lat, longitude: lon)
    }
    private var coordinates: [CLLocationCoordinate2D] { points.map { $0.coordinate } }
    private var averageSpeedMps: Double { elapsed > 0 ? distanceMeters / elapsed : 0 }
    private var currentSpeedMps: Double {
        guard let lastT = lastTimestamp, let lastC = lastCoord,
              let newC = currentCoordinate, let newT = lm.lastFix else { return 0 }
        let dt = newT.timeIntervalSince(lastT); guard dt > 0.1 else { return 0 }
        let d = CLLocation(latitude: lastC.latitude, longitude: lastC.longitude)
            .distance(from: CLLocation(latitude: newC.latitude, longitude: newC.longitude))
        return d / dt
    }
    private var originCoord: CLLocationCoordinate2D? {
        guard let t = Maff.parseLatLon(overlayOriginString) else { return nil }
        return .init(latitude: t.lat, longitude: t.lon)
    }
    private var targetCoord: CLLocationCoordinate2D? {
        guard let t = Maff.parseLatLon(overlayTargetString) else { return nil }
        return .init(latitude: t.lat, longitude: t.lon)
    }
    private var originToTargetPolyline: MKPolyline? {
        guard let o = originCoord, let t = targetCoord else { return nil }
        var coords = [o, t]; return MKPolyline(coordinates: &coords, count: 2)
    }

    private func startRecording() {
        resetSession(); isRecording = true; startTime = Date()
        if let c = currentCoordinate { appendPoint(at: c, time: lm.lastFix ?? Date()) }
    }
    private func stopRecording() { isRecording = false }
    private func resetSession() {
        isRecording = false; points.removeAll(); distanceMeters = 0; elapsed = 0
        startTime = nil; maxSpeedMps = 0; lastCoord = nil; lastTimestamp = nil
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
                if dt > 0.1 { maxSpeedMps = max(maxSpeedMps, d / dt) }
                appendPoint(at: newC, time: now)
            }
        } else {
            appendPoint(at: newC, time: now)
        }
    }
    private func appendPoint(at coord: CLLocationCoordinate2D, time: Date) {
        let alt = lm.altitudeMSL ?? 0
        points.append(TrackPoint(coordinate: coord, altitudeMSL: alt, timestamp: time))
        lastCoord = coord; lastTimestamp = time
    }

    private func exportGpx() {
        guard points.count >= 2 else { return }
        let header = """
        <?xml version="1.0" encoding="UTF-8"?>
        <gpx version="1.1" creator="GNSS Toolkit" xmlns="http://www.topografix.com/GPX/1/1">
          <trk>
            <name>Track \(Maff.DateFormats.gpxFileStamp.string(from: startTime ?? Date()))</name>
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
        let gpx = [header, body, footer].joined(separator: "\n")
        let filename = "Track-\(Maff.DateFormats.gpxFileStamp.string(from: Date())).gpx"
        if let url = writeTempFile(named: filename, contents: Data(gpx.utf8)) {
            shareURL = url; showShare = true
        }
    }
    private func writeTempFile(named: String, contents: Data) -> URL? {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(named)
        do { try contents.write(to: url, options: .atomic); return url }
        catch { print("Failed to write file: \(error)"); return nil }
    }
    private func removeTemp(_ url: URL) { try? FileManager.default.removeItem(at: url) }

    private func stat(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).foregroundStyle(.secondary)
            Text(value)
        }.mono10()
    }
}
