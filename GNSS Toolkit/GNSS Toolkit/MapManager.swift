//
//  MapManager.swift
//  GNSS Toolkit
//
//  Created by Simon Chu on 9/1/25.
//

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

    // HUD page order: 0 Controls, 1 Geofence, 2 Set Info, 3 Origin, 4 Target
    @State private var hudPage: Int = 0
    private let hudLastIndex = 4

    // Geofence: keep meters internally; accept/display in current unit
    @State private var fenceInputField: String = ""      // user's numeric input (in current unit)
    @State private var fenceRadiusMeters: Double? = nil  // active fence (meters)

    var body: some View {
        NavigationStack {
            ZStack {
                mapLayer

                // Header pinned high, map expands beneath
                VStack(spacing: 8) {
                    headerBar
                    Spacer(minLength: 0)
                }
                .padding(.horizontal)
                .padding(.top, 6)

                // HUD pinned near bottom
                VStack(spacing: 10) {
                    Spacer(minLength: 0)
                    hud
                }
                .padding(.horizontal)
                .padding(.bottom, 10)
            }
            .navigationTitle("") // custom header
            .navigationBarTitleDisplayMode(.inline)
        }
        .environment(\.font, AppTheme.baseFont)
    }

    // MARK: - Map

    @ViewBuilder
    private var mapLayer: some View {
        MapReader { proxy in
            Map(position: $camera, interactionModes: .all) {
                // Origin annotation (blue downward triangle)
                if let o = origin {
                    Annotation("Origin", coordinate: o.coordinate) {
                        Image(systemName: "triangle.fill")
                            .rotationEffect(.degrees(180)) // point down
                            .foregroundStyle(.blue)
                            .shadow(radius: 2)
                    }
                }

                // Target annotation (red downward triangle)
                if let t = target {
                    Annotation("Target", coordinate: t.coordinate) {
                        Image(systemName: "triangle.fill")
                            .rotationEffect(.degrees(180))
                            .foregroundStyle(.red)
                            .shadow(radius: 2)
                    }
                }

                // Distance line (solid orange)
                if let line = linePolyline {
                    MapPolyline(line)
                        .stroke(.orange, lineWidth: 2)
                }

                // Geofence: dotted red circle + outside red overlay
                if let o = origin, let r = fenceRadiusMeters, r > 0 {
                    MapCircle(center: o.coordinate, radius: r)
                        .stroke(.red, style: StrokeStyle(lineWidth: 2, dash: [6, 6]))

                    if let maskPolygon = geofenceOutsidePolygon(center: o.coordinate, radius: r) {
                        MapPolygon(maskPolygon)
                            .foregroundStyle(Color.red.opacity(0.15))
                    }
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
            // Long-press anywhere to set the target point
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
        .ignoresSafeArea(.keyboard) // map shouldn't jump when keyboard appears
    }

    // MARK: - Header (icon left, title higher, quick center on right)

    private var headerBar: some View {
        HStack(spacing: 8) {
            Image("Icon-DEV")
                .resizable()
                .scaledToFit()
                .frame(width: 22, height: 22)
                .clipShape(RoundedRectangle(cornerRadius: 4))
                .overlay(RoundedRectangle(cornerRadius: 4).stroke(.secondary.opacity(0.3), lineWidth: 0.5))

            Text("Map Manager")
                .monoTitle()

            Spacer()

            // Quick "Center on Me" (top-right)
            Button {
                centerOnMe()
            } label: {
                Image(systemName: "location.fill")
                    .imageScale(.medium)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(.thinMaterial, in: Capsule())
                    .overlay(Capsule().stroke(.secondary.opacity(0.25)))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(.ultraThinMaterial, in: Capsule())
        .overlay(Capsule().stroke(.secondary.opacity(0.25)))
        .mono10()
    }

    // MARK: - HUD

    private var hud: some View {
        VStack(spacing: 6) {
            // wrap-aware little pager (tap to wrap; swipes still work normally)
            HStack(spacing: 10) {
                Button("◀︎") { prevHUD() }
                    .mono10()
                    .padding(.horizontal, 8).padding(.vertical, 4)
                    .background(.thinMaterial, in: Capsule())
                    .overlay(Capsule().stroke(.secondary.opacity(0.25)))

                Spacer()

                Button("▶︎") { nextHUD() }
                    .mono10()
                    .padding(.horizontal, 8).padding(.vertical, 4)
                    .background(.thinMaterial, in: Capsule())
                    .overlay(Capsule().stroke(.secondary.opacity(0.25)))
            }
            .padding(.horizontal, 6)

            TabView(selection: $hudPage) {
                controlCard.tag(0)     // Controls FIRST
                fenceCard.tag(1)       // Geofence SECOND
                setInfoCard.tag(2)     // Set Info THIRD (incl geofence dist)
                hudCard(for: origin, title: "Origin").tag(3)
                hudCard(for: target, title: "Target").tag(4)
            }
            .tabViewStyle(.page(indexDisplayMode: .always))
            .frame(maxHeight: 170)
        }
    }

    // 0) Controls tab (Origin + Target inputs)
    private var controlCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Controls").monoTitle()

            HStack {
                Button(action: { setOriginFromCurrentFix() }) {
                    labelButton("Get Origin (from current)")
                }
                .frame(maxWidth: .infinity)
            }

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
            }

            HStack(spacing: 8) {
                Button(action: { origin = nil }) {
                    labelButton("Clear Origin")
                }
                .frame(maxWidth: .infinity)

                Button(action: { target = nil }) {
                    labelButton("Clear Target")
                }
                .frame(maxWidth: .infinity)
            }
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(.thinMaterial))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(.secondary.opacity(0.15), lineWidth: 1))
        .mono10()
    }

    // 1) Geofence tab (unit-aware)
    private var fenceCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Geofence").monoTitle()

            VStack(alignment: .leading, spacing: 8) {
                row("Origin", origin != nil ? "\(fmt(origin!.lat)), \(fmt(origin!.lon))" : "--")
                row("Radius", fenceRadiusMeters.flatMap { Maff.distanceText(fromMeters: $0, useFeet: useFeet) } ?? "--")
            }

            HStack(spacing: 8) {
                ForEach(presetDistancesDisplay, id: \.self) { label in
                    Button(label) {
                        if let numeric = Double(label.filter("0123456789.".contains)) {
                            fenceInputField = String(numeric)
                        }
                    }
                    .mono10()
                    .padding(.horizontal, 8)
                    .padding(.vertical, 6)
                    .background(.thinMaterial, in: Capsule())
                    .overlay(Capsule().stroke(.secondary.opacity(0.25)))
                }
            }

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
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(.thinMaterial))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(.secondary.opacity(0.15), lineWidth: 1))
        .mono10()
    }

    // 2) Set Info tab (delta + geofence info)
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

    // Reusable details card
    private func hudCard(for p: PointInfo?, title: String) -> some View {
        let mode   = Maff.TimeMode(rawValue: timeModeRaw) ?? .utc
        let latStr  = p.map { fmt($0.lat) } ?? "--"
        let lonStr  = p.map { fmt($0.lon) } ?? "--"
        let mslStr  = Maff.distanceText(fromMeters: p?.msl, useFeet: useFeet)
        let aglStr  = Maff.distanceText(fromMeters: p?.agl, useFeet: useFeet)
        let timeStr = Maff.timeText(date: p?.timestamp, mode: mode)

        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(title).monoTitle()
                Spacer()
                Text("◀︎ swipe ▶︎").foregroundStyle(.secondary).mono10()
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
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(.thinMaterial))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(.secondary.opacity(0.15), lineWidth: 1))
        .mono10()
    }

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

    // MARK: - Pager wrap

    private func nextHUD() {
        hudPage = (hudPage + 1) > hudLastIndex ? 0 : (hudPage + 1)
    }

    private func prevHUD() {
        hudPage = (hudPage - 1) < 0 ? hudLastIndex : (hudPage - 1)
    }

    // MARK: - Helpers

    private func setOriginFromCurrentFix() {
        guard let lat = lm.latitude, let lon = lm.longitude else { return }
        origin = PointInfo(lat: lat,
                           lon: lon,
                           msl: lm.altitudeMSL,
                           agl: lm.altitudeAGL,
                           timestamp: lm.lastFix)
        let span = MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01)
        let reg  = MKCoordinateRegion(center: origin!.coordinate, span: span)
        withAnimation(.easeInOut) { camera = .region(reg) }
    }

    private func setTarget(from coord: CLLocationCoordinate2D, msl: Double?, agl: Double?, date: Date?) {
        target = PointInfo(lat: coord.latitude,
                           lon: coord.longitude,
                           msl: msl,
                           agl: agl,
                           timestamp: date)
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
        // Accepts "lat,lon" with optional spaces
        let parts = text.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
        guard parts.count == 2, let lat = Double(parts[0]), let lon = Double(parts[1]),
              abs(lat) <= 90, abs(lon) <= 180 else { return nil }
        return .init(latitude: lat, longitude: lon)
    }

    /// 6-decimal coordinate string (e.g., 32.715300)
    private func fmt(_ v: Double, decimals: Int = 6) -> String {
        String(format: "%.\(decimals)f", v)
    }

    // MARK: Geofence helpers (unit-aware)

    private var currentUnitAbbrev: String { useFeet ? "ft" : "m" }

    private var presetDistancesDisplay: [String] {
        useFeet ? ["100ft", "250ft", "500ft", "1000ft"]
                : ["50m", "100m", "250m", "500m"]
    }

    /// Convert a numeric value in the CURRENT unit to meters.
    private func toMeters(fromCurrentUnit value: Double) -> Double {
        useFeet ? (value / Maff.feetPerMeter) : value
    }

    private func applyFenceFromInput() {
        guard origin != nil else {
            fenceRadiusMeters = nil
            return
        }
        guard let val = Double(fenceInputField), val > 0 else {
            fenceRadiusMeters = nil
            return
        }
        fenceRadiusMeters = toMeters(fromCurrentUnit: val)

        // (Optional) keep view centered on origin when fence changes
        if let o = origin {
            let span = MKCoordinateSpan(latitudeDelta: 0.02, longitudeDelta: 0.02)
            let reg  = MKCoordinateRegion(center: o.coordinate, span: span)
            withAnimation(.easeInOut) { camera = .region(reg) }
        }
    }

    // Build an MKPolygon that fills most of the world with a circular "hole" for the fence
    private func geofenceOutsidePolygon(center: CLLocationCoordinate2D, radius: Double) -> MKPolygon? {
        let circlePoly = circlePolygon(center: center, radius: radius, points: 180)

        // Big outer square (avoid poles for sanity)
        let outer: [CLLocationCoordinate2D] = [
            CLLocationCoordinate2D(latitude: 85,  longitude: -180),
            CLLocationCoordinate2D(latitude: 85,  longitude:  180),
            CLLocationCoordinate2D(latitude: -85, longitude:  180),
            CLLocationCoordinate2D(latitude: -85, longitude: -180)
        ]
        let outerPoly = MKPolygon(coordinates: outer, count: outer.count, interiorPolygons: [circlePoly])
        return outerPoly
    }

    // Create a polygon approximating a circle on Earth’s surface
    private func circlePolygon(center: CLLocationCoordinate2D, radius: Double, points: Int) -> MKPolygon {
        let lat = center.latitude * .pi / 180
        let lon = center.longitude * .pi / 180
        let d   = radius / Haversine.R

        var coords: [CLLocationCoordinate2D] = []
        coords.reserveCapacity(points)
        for i in 0..<points {
            let bearing = 2 * .pi * Double(i) / Double(points)
            // spherical law of cosines
            let lat2 = asin( sin(lat) * cos(d) + cos(lat) * sin(d) * cos(bearing) )
            let lon2 = lon + atan2( sin(bearing) * sin(d) * cos(lat),
                                    cos(d) - sin(lat) * sin(lat2) )
            coords.append(CLLocationCoordinate2D(latitude: lat2 * 180 / .pi,
                                                 longitude: lon2 * 180 / .pi))
        }
        return MKPolygon(coordinates: &coords, count: coords.count)
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
        DeltaInfo(distanceMeters: nil,
                  bearingDegrees: nil,
                  distanceText: "--",
                  bearingText: "--",
                  cardinal: "--")
    }

    static func make(distanceMeters: Double, bearingDegrees: Double, useFeet: Bool) -> DeltaInfo {
        let dist = Maff.distanceText(fromMeters: distanceMeters, useFeet: useFeet)
        let brg  = String(format: "%.1f°", bearingDegrees)
        let card = Bearing.cardinal(from: bearingDegrees)
        return .init(distanceMeters: distanceMeters,
                     bearingDegrees: bearingDegrees,
                     distanceText: dist,
                     bearingText: brg,
                     cardinal: card)
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
        let d = deg(θ)
        // normalize to [0,360)
        return (d.truncatingRemainder(dividingBy: 360) + 360).truncatingRemainder(dividingBy: 360)
    }

    static func cardinal(from degs: Double) -> String {
        // 16-wind compass
        let dirs = ["N","NNE","NE","ENE","E","ESE","SE","SSE",
                    "S","SSW","SW","WSW","W","WNW","NW","NNW"]
        let idx = Int((degs/22.5).rounded()) % 16
        return dirs[idx]
    }
}
