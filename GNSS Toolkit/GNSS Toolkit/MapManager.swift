//  MapManager.swift
//  GNSS Toolkit
//
//  Option B: full-bleed map (no NavigationStack), center-on-me overlay,
//  HUD without pager arrows, Controls header actions, Geofence presets on
//  their own line, and geofence outline-only (transparent fill).

import SwiftUI
import MapKit

struct MapManager: View {
    @ObservedObject var lm: LocationManager

    // Persisted display options
    @AppStorage("useFeet") private var useFeet = false
    @AppStorage("timeMode") private var timeModeRaw: String = Maff.TimeMode.utc.rawValue

    // Stored points (snapshotted when set)
    @State private var origin: PointInfo? = nil
    @State private var target: PointInfo? = nil

    // Map state
    @State private var camera: MapCameraPosition = .userLocation(fallback: .automatic)
    @State private var userCenteredOnce = false

    // Lat,lon input (e.g., "32.7153,-117.1573")
    @State private var latlonField: String = ""
    @FocusState private var latlonFocused: Bool

    // HUD pages: 0 Controls, 1 Geofence, 2 Set Info, 3 Origin, 4 Target
    @State private var hudPage: Int = 0

    // Geofence (meters internally)
    @State private var fenceInputField: String = ""
    @State private var fenceRadiusMeters: Double? = nil

    var body: some View {
        ZStack {
            mapLayer

            // Top-right center button
            VStack {
                HStack {
                    Spacer()
                    Button { centerOnMe() } label: {
                        Image(systemName: "location.fill")
                            .imageScale(.medium)
                            .padding(12)
                            .background(.ultraThinMaterial, in: Circle())
                            .overlay(Circle().stroke(.secondary.opacity(0.25)))
                            .frame(minWidth: 44, minHeight: 44)
                    }
                    .buttonStyle(.plain)
                    .padding(.trailing, 12)
                }
                .padding(.top, 2)

                Spacer()
            }
            .allowsHitTesting(true)

            // Bottom HUD
            VStack(spacing: 10) {
                Spacer(minLength: 0)
                hud
            }
            .padding(.horizontal)
            .padding(.bottom, 10)
        }
        .environment(\.font, AppTheme.baseFont)
    }

    // MARK: - Map layer
    @ViewBuilder
    private var mapLayer: some View {
        MapReader { proxy in
            Map(position: $camera, interactionModes: .all) {
                // Origin annotation
                if let o = origin {
                    Annotation("Origin", coordinate: o.coordinate) {
                        Image(systemName: "triangle.fill")
                            .rotationEffect(.degrees(180))
                            .foregroundStyle(.blue)
                            .shadow(radius: 2)
                    }
                }
                // Target annotation
                if let t = target {
                    Annotation("Target", coordinate: t.coordinate) {
                        Image(systemName: "triangle.fill")
                            .rotationEffect(.degrees(180))
                            .foregroundStyle(.red)
                            .shadow(radius: 2)
                    }
                }
                // Line between origin and target
                if let line = linePolyline {
                    MapPolyline(line)
                        .stroke(.orange, lineWidth: 2)
                }
                // Geofence (outline-only)
                if let o = origin, let r = fenceRadiusMeters, r > 0 {
                    MapCircle(center: o.coordinate, radius: r)
                        .stroke(.red, lineWidth: 2)
                        .foregroundStyle(.clear)
                }
            }
            .onMapCameraChange { _ in
                if !userCenteredOnce, let lat = lm.latitude, let lon = lm.longitude {
                    userCenteredOnce = true
                    let span = MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01)
                    let reg  = MKCoordinateRegion(center: .init(latitude: lat, longitude: lon), span: span)
                    withAnimation(.easeInOut) { camera = .region(reg) }
                }
            }
            // Long-press + slight drag to drop Target
            .gesture(
                LongPressGesture(minimumDuration: 0.35)
                    .sequenced(before: DragGesture(minimumDistance: 0))
                    .onEnded { value in
                        switch value {
                        case .second(true, let drag?):
                            let p = drag.location
                            if let coord = proxy.convert(p, from: .local) {
                                setTarget(from: coord, msl: lm.altitudeMSL, agl: lm.altitudeAGL, date: lm.lastFix)
                            }
                        default: break
                        }
                    }
            )
        }
        .ignoresSafeArea()
        .ignoresSafeArea(.keyboard)
    }

    // MARK: - HUD
    private var hud: some View {
        VStack(spacing: 6) {
            TabView(selection: $hudPage) {
                controlCard.tag(0)
                fenceCard.tag(1)
                setInfoCard.tag(2)
                hudCard(for: origin, title: "Origin", isOriginCard: true).tag(3)
                hudCard(for: target, title: "Target", isOriginCard: false).tag(4)
            }
            .tabViewStyle(.page(indexDisplayMode: .always))
            .frame(maxHeight: 200)
        }
    }

    // Controls card
    private var controlCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header: title left, actions right
            HStack(spacing: 8) {
                Text("Controls").monoTitle()
                Spacer()
                HStack(spacing: 8) {
                    Button(action: { setOriginFromCurrentFix() }) { labelButton("Set Origin") }
                    Button(action: { origin = nil }) { labelButton("Clear Origin") }
                    Button(action: { target = nil }) { labelButton("Clear Target") }
                }
            }

            // Target entry
            HStack(spacing: 8) {
                TextField("lat,lon  (e.g. 32.7153,-117.1573)", text: $latlonField)
                    .textFieldStyle(.roundedBorder)
                    .focused($latlonFocused)

                Button("Set Target") {
                    if let c = parseLatLon(latlonField) {
                        setTarget(from: c, msl: nil, agl: nil, date: Date())
                        latlonFocused = false
                    }
                }
                .buttonStyle(.bordered)
            }

            // Readouts
            let d = delta
            VStack(alignment: .leading, spacing: 6) {
                row("Distance",  d.distanceText)
                row("Bearing",   d.bearingText)
                row("Direction", d.cardinal)
            }
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(.thinMaterial))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(.secondary.opacity(0.15), lineWidth: 1))
        .mono10()
    }

    // Geofence card
    private var fenceCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Title + quick Set Origin
            HStack(spacing: 8) {
                Text("Geofence").monoTitle()
                Spacer()
                Button(action: { setOriginFromCurrentFix() }) { labelButton("Set Origin") }
            }

            // Distance field row
            HStack(spacing: 8) {
                TextField("Distance (\(currentUnitAbbrev))", text: $fenceInputField)
                    .keyboardType(.decimalPad)
                    .textFieldStyle(.roundedBorder)

                Button("Set Fence") { applyFenceFromInput() }
                    .buttonStyle(.bordered)
                Button("Clear Fence") {
                    fenceRadiusMeters = nil
                    fenceInputField = ""
                }
                .buttonStyle(.bordered)
            }

            // Presets on next line
            HStack(spacing: 8) {
                quickButton("100m", meters: 100)
                quickButton("500m", meters: 500)
                quickButton("1km",  meters: 1_000)
                quickButton("5km",  meters: 5_000)
                quickButton("10km", meters: 10_000)
            }

            // Readouts
            VStack(alignment: .leading, spacing: 6) {
                row("Origin", origin != nil ? "\(fmt(origin!.lat)), \(fmt(origin!.lon))" : "--")
                row("Radius", fenceRadiusMeters.flatMap { Maff.distanceText(fromMeters: $0, useFeet: useFeet) } ?? "--")
            }
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(.thinMaterial))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(.secondary.opacity(0.15), lineWidth: 1))
        .mono10()
    }

    private func quickButton(_ title: String, meters: Double) -> some View {
        Button(action: { setFenceQuick(meters: meters) }) {
            Text(title)
                .mono10()
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .background(.thinMaterial, in: Capsule())
                .overlay(Capsule().stroke(.secondary.opacity(0.25)))
        }
    }

    // Set Info card
    private var setInfoCard: some View {
        let d = delta
        let fenceText = fenceRadiusMeters.flatMap { Maff.distanceText(fromMeters: $0, useFeet: useFeet) } ?? "--"

        return VStack(alignment: .leading, spacing: 8) {
            Text("Set Info").monoTitle()
            VStack(alignment: .leading, spacing: 6) {
                row("Distance",  d.distanceText)
                row("Bearing",   d.bearingText)
                row("Direction", d.cardinal)
                row("Geofence",  fenceText)
            }
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(.thinMaterial))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(.secondary.opacity(0.15), lineWidth: 1))
        .mono10()
    }

    // Origin/Target details card
    private func hudCard(for p: PointInfo?, title: String, isOriginCard: Bool) -> some View {
        let mode   = Maff.TimeMode(rawValue: timeModeRaw) ?? .utc
        let latStr  = p.map { fmt($0.lat) } ?? "--"
        let lonStr  = p.map { fmt($0.lon) } ?? "--"
        let mslStr  = Maff.distanceText(fromMeters: p?.msl, useFeet: useFeet)
        let aglStr  = Maff.distanceText(fromMeters: p?.agl, useFeet: useFeet)
        let timeStr = Maff.timeText(date: p?.timestamp, mode: mode)

        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(title).monoTitle()
                Spacer()
            }

            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    row("Lat",  latStr)
                    row("Long", lonStr)
                }
                VStack(alignment: .leading, spacing: 4) {
                    row("MSL", mslStr)
                    row("AGL", aglStr)
                }
                VStack(alignment: .leading, spacing: 4) {
                    row("UTC", timeStr)
                }
            }

            HStack(spacing: 8) {
                if isOriginCard {
                    Button(action: { setOriginFromCurrentFix() }) { labelButton("Set Origin") }
                    Button(action: { origin = nil }) { labelButton("Clear Origin") }
                } else {
                    Button(action: { target = nil }) { labelButton("Clear Target") }
                }
            }
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(.thinMaterial))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(.secondary.opacity(0.15), lineWidth: 1))
        .mono10()
    }

    // MARK: - Small UI helpers
    private func row(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label).foregroundStyle(.secondary)
            Spacer(minLength: 8)
            Text(value)
        }
    }

    private func labelButton(_ title: String) -> some View {
        Text(title)
            .mono10()
            .lineLimit(1)
            .minimumScaleFactor(0.85)
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(.thinMaterial, in: Capsule())
            .overlay(Capsule().stroke(.secondary.opacity(0.25)))
    }

    // MARK: - Actions/Logic
    private func setOriginFromCurrentFix() {
        guard let lat = lm.latitude, let lon = lm.longitude else { return }
        origin = PointInfo(lat: lat, lon: lon, msl: lm.altitudeMSL, agl: lm.altitudeAGL, timestamp: lm.lastFix)
        let span = MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01)
        let reg  = MKCoordinateRegion(center: origin!.coordinate, span: span)
        withAnimation(.easeInOut) { camera = .region(reg) }
    }

    private func setTarget(from coord: CLLocationCoordinate2D, msl: Double?, agl: Double?, date: Date?) {
        target = PointInfo(lat: coord.latitude, lon: coord.longitude, msl: msl, agl: agl, timestamp: date)
    }

    private func centerOnMe() {
        guard let lat = lm.latitude, let lon = lm.longitude else { return }
        let span = MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01)
        let reg  = MKCoordinateRegion(center: .init(latitude: lat, longitude: lon), span: span)
        withAnimation(.easeInOut) { camera = .region(reg) }
    }

    private var linePolyline: MKPolyline? {
        guard let o = origin, let t = target else { return nil }
        var coords = [o.coordinate, t.coordinate]
        return MKPolyline(coordinates: &coords, count: 2)
    }

    private var delta: DeltaInfo {
        guard let o = origin, let t = target else {
            return .empty(useFeet: useFeet)
        }
        let meters  = Haversine.distanceMeters(from: o.coordinate, to: t.coordinate)
        let bearing = Bearing.initialDegrees(from: o.coordinate, to: t.coordinate)
        return .make(distanceMeters: meters, bearingDegrees: bearing, useFeet: useFeet)
    }

    private func parseLatLon(_ text: String) -> CLLocationCoordinate2D? {
        let parts = text.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
        guard parts.count == 2, let lat = Double(parts[0]), let lon = Double(parts[1]), abs(lat) <= 90, abs(lon) <= 180 else { return nil }
        return .init(latitude: lat, longitude: lon)
    }

    private func fmt(_ v: Double, decimals: Int = 6) -> String {
        String(format: "% .\(decimals)f", v)
    }

    private var currentUnitAbbrev: String { useFeet ? "ft" : "m" }

    private func toMeters(fromCurrentUnit value: Double) -> Double {
        useFeet ? (value / Maff.feetPerMeter) : value
    }

    private func setFenceQuick(meters: Double) {
        guard origin != nil else { return }
        fenceRadiusMeters = meters
        let uiValue = useFeet ? (meters * Maff.feetPerMeter) : meters
        fenceInputField = String(format: "%.0f", uiValue)
        recenterForFence()
    }

    private func applyFenceFromInput() {
        guard origin != nil else { fenceRadiusMeters = nil; return }
        guard let val = Double(fenceInputField), val > 0 else { fenceRadiusMeters = nil; return }
        fenceRadiusMeters = toMeters(fromCurrentUnit: val)
        recenterForFence()
    }

    private func recenterForFence() {
        if let o = origin {
            let span = MKCoordinateSpan(latitudeDelta: 0.02, longitudeDelta: 0.02)
            let reg  = MKCoordinateRegion(center: o.coordinate, span: span)
            withAnimation(.easeInOut) { camera = .region(reg) }
        }
    }

    // MARK: - Models & Math
    private struct PointInfo {
        let lat: Double
        let lon: Double
        let msl: Double?
        let agl: Double?
        let timestamp: Date?
        var coordinate: CLLocationCoordinate2D { .init(latitude: lat, longitude: lon) }
    }

    private struct DeltaInfo {
        let distanceMeters: Double?
        let bearingDegrees: Double?

        let distanceText: String
        let bearingText: String
        let cardinal: String

        static func empty(useFeet: Bool) -> DeltaInfo {
            DeltaInfo(distanceMeters: nil, bearingDegrees: nil, distanceText: "--", bearingText: "--", cardinal: "--")
        }

        static func make(distanceMeters: Double, bearingDegrees: Double, useFeet: Bool) -> DeltaInfo {
            let dist = Maff.distanceText(fromMeters: distanceMeters, useFeet: useFeet)
            let brg  = String(format: "%.1f°", bearingDegrees)
            let card = Bearing.cardinal(from: bearingDegrees)
            return .init(distanceMeters: distanceMeters, bearingDegrees: bearingDegrees, distanceText: dist, bearingText: brg, cardinal: card)
        }
    }

    private enum Haversine {
        static let R: Double = 6_371_000 // Earth radius in meters
        static func distanceMeters(from a: CLLocationCoordinate2D, to b: CLLocationCoordinate2D) -> Double {
            func rad(_ d: Double) -> Double { d * .pi / 180 }
            let dLat = rad(b.latitude - a.latitude)
            let dLon = rad(b.longitude - a.longitude)
            let lat1 = rad(a.latitude), lat2 = rad(b.latitude)
            let h = sin(dLat/2)*sin(dLat/2) + cos(lat1)*cos(lat2)*sin(dLon/2)*sin(dLon/2)
            let c = 2 * atan2(sqrt(h), sqrt(1 - h))
            return R * c
        }
    }

    private enum Bearing {
        static func initialDegrees(from a: CLLocationCoordinate2D, to b: CLLocationCoordinate2D) -> Double {
            func rad(_ d: Double) -> Double { d * .pi / 180 }
            func deg(_ r: Double) -> Double { r * 180 / .pi }
            let φ1 = rad(a.latitude), φ2 = rad(b.latitude)
            let λ1 = rad(a.longitude), λ2 = rad(b.longitude)
            let y = sin(λ2 - λ1) * cos(φ2)
            let x = cos(φ1) * sin(φ2) - sin(φ1) * cos(φ2) * cos(λ2 - λ1)
            let θ = atan2(y, x)
            // normalize to [0,360)
            return (deg(θ).truncatingRemainder(dividingBy: 360) + 360).truncatingRemainder(dividingBy: 360)
        }
        static func cardinal(from degs: Double) -> String {
            let dirs = ["N","NNE","NE","ENE","E","ESE","SE","SSE","S","SSW","SW","WSW","W","WNW","NW","NNW"]
            let idx = Int((degs/22.5).rounded()) % 16
            return dirs[idx]
        }
    }
}
