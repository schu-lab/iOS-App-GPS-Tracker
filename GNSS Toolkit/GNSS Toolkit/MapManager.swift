//  MapManager.swift
//  GNSS Toolkit
//
//  Lightweight manager-style map with Origin/Target markers, Origin→Target line,
//  geofence circle outline, and simple controls.
//  Relies on shared helpers in Maff.swift (parseLatLon, distanceText, etc.)

import SwiftUI
import MapKit
import CoreLocation

struct MapManager: View {
    @ObservedObject var lm: LocationManager

    // Display prefs
    @AppStorage("useFeet") private var useFeet = false

    // Overlays shared across tabs
    @AppStorage("overlay_origin") private var overlayOriginString: String = ""   // "lat,lon"
    @AppStorage("overlay_target") private var overlayTargetString: String = ""   // "lat,lon"
    @AppStorage("overlay_fence_m") private var overlayFenceMeters: Double = 0    // meters

    // Map camera
    @State private var camera: MapCameraPosition = .userLocation(fallback: .automatic)
    @State private var didInitialCenter = false

    // Geofence input
    @State private var fenceInput: String = ""   // accepts meters (e.g., "500" or "1500")

    var body: some View {
        ZStack {
            VStack(spacing: 12) {
                // === Map ===
                Map(position: $camera, interactionModes: .all) {
                    // You
                    UserAnnotation()

                    // Origin marker
                    if let o = originCoord {
                        Annotation("Origin", coordinate: o) {
                            Image(systemName: "triangle.fill")
                                .rotationEffect(.degrees(180))
                                .foregroundStyle(.blue)
                                .shadow(radius: 1.5)
                        }
                    }

                    // Target marker
                    if let t = targetCoord {
                        Annotation("Target", coordinate: t) {
                            Image(systemName: "triangle.fill")
                                .rotationEffect(.degrees(180))
                                .foregroundStyle(.red)
                                .shadow(radius: 1.5)
                        }
                    }

                    // Origin → Target line
                    if let line = originToTargetPolyline {
                        MapPolyline(line)
                            .stroke(.orange, lineWidth: 2)
                    }

                    // Geofence (outline only, no fill)
                    if let o = originCoord, overlayFenceMeters > 0 {
                        MapCircle(center: o, radius: overlayFenceMeters)
                            .stroke(.red, lineWidth: 2)
                            .foregroundStyle(.clear)
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(.secondary.opacity(0.25), lineWidth: 0.5))
                .padding(.horizontal, 12)
                .padding(.top, 6)
                .onMapCameraChange { _ in
                    if !didInitialCenter, let c = currentCoordinate {
                        didInitialCenter = true
                        let span = MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01)
                        camera = .region(MKCoordinateRegion(center: c, span: span))
                    }
                }

                // === HUD (compact) ===
                VStack(spacing: 6) {
                    HStack {
                        stat("Lat", latText)
                        Spacer(minLength: 8)
                        stat("Lon", lonText)
                        Spacer(minLength: 8)
                        stat("Fence", Maff.distanceText(fromMeters: overlayFenceMeters, useFeet: useFeet))
                        Spacer()
                    }
                    .monospacedDigit()
                }
                .padding(10)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(.secondary.opacity(0.25), lineWidth: 0.5))
                .padding(.horizontal, 12)

                // === Controls ===
                VStack(spacing: 10) {
                    // Row 1: Origin / Target
                    HStack(spacing: 10) {
                        Button("Set Origin", action: setOriginFromCurrent)
                            .buttonStyle(.borderedProminent)
                            .controlSize(.small)

                        Button("Clear Origin") { overlayOriginString = "" }
                            .buttonStyle(.bordered)
                            .controlSize(.small)

                        Spacer(minLength: 8)

                        Button("Set Target", action: setTargetFromCurrent)
                            .buttonStyle(.borderedProminent)
                            .controlSize(.small)

                        Button("Clear Target") { overlayTargetString = "" }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                    }

                    // Row 2: Fence quick set
                    HStack(spacing: 8) {
                        Text("Fence:")
                            .foregroundStyle(.secondary)
                            .mono10()

                        ForEach([100.0, 500.0, 1000.0, 2000.0, 5000.0, 10000.0], id: \.self) { m in
                            Button(action: { overlayFenceMeters = m }) {
                                Text(shortDistanceText(m))
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                        }

                        Spacer(minLength: 8)

                        Button("Clear Fence") { overlayFenceMeters = 0 }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                    }

                    // Row 3: Fence numeric input
                    HStack(spacing: 8) {
                        TextField("Fence (m)", text: $fenceInput)
                            .textFieldStyle(.roundedBorder)
                            .keyboardType(.decimalPad)
                            .frame(maxWidth: 140)

                        Button("Apply", action: applyFenceFromInput)
                            .buttonStyle(.borderedProminent)
                            .controlSize(.small)

                        Spacer(minLength: 8)

                        Button {
                            if let c = currentCoordinate {
                                withAnimation(.easeInOut) {
                                    camera = .region(MKCoordinateRegion(center: c,
                                                                        span: MKCoordinateSpan(latitudeDelta: 0.004,
                                                                                               longitudeDelta: 0.004)))
                                }
                            }
                        } label: {
                            Label("Recenter", systemImage: "location.north.line")
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.bottom, 8)
            }

            // === Title bar (top-left) ===
            VStack {
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
                }
                .padding(.horizontal, 12)
                .padding(.top, 8)

                Spacer()
            }
        }
        .padding(.bottom, 2)
        .environment(\.font, AppTheme.baseFont)
    }

    // MARK: - Derived

    private var currentCoordinate: CLLocationCoordinate2D? {
        guard let lat = lm.latitude, let lon = lm.longitude else { return nil }
        return CLLocationCoordinate2D(latitude: lat, longitude: lon)
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
        var coords = [o, t]
        return MKPolyline(coordinates: &coords, count: 2)
    }

    // MARK: - UI helpers

    private func stat(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).foregroundStyle(.secondary)
            Text(value)
        }
        .mono10()
    }

    private var latText: String {
        if let v = lm.latitude { return String(format: "%.6f", v) }
        return "--"
    }
    private var lonText: String {
        if let v = lm.longitude { return String(format: "%.6f", v) }
        return "--"
    }

    private func shortDistanceText(_ meters: Double) -> String {
        if useFeet {
            if meters >= 1000 {
                let miles = meters * 0.000621371
                return String(format: "%.0f mi", miles.rounded())
            } else {
                let feet = meters * Maff.feetPerMeter
                return String(format: "%.0f ft", feet.rounded())
            }
        } else {
            if meters >= 1000 {
                return String(format: "%.0f km", meters / 1000)
            } else {
                return String(format: "%.0f m", meters)
            }
        }
    }

    private func applyFenceFromInput() {
        let cleaned = fenceInput.trimmingCharacters(in: .whitespacesAndNewlines)
        if let m = Double(cleaned), m >= 0 {
            overlayFenceMeters = m
        }
        fenceInput = ""
    }

    private func setOriginFromCurrent() {
        guard let c = currentCoordinate else { return }
        overlayOriginString = String(format: "%.6f, %.6f", c.latitude, c.longitude)
    }

    private func setTargetFromCurrent() {
        guard let c = currentCoordinate else { return }
        overlayTargetString = String(format: "%.6f, %.6f", c.latitude, c.longitude)
    }
}
