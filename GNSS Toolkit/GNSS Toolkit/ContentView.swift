//
//  ContentView.swift
//  GNSS Toolkit
//
//  Created by Simon Chu on 9/1/25.
//

import SwiftUI
import UIKit   // for UIPasteboard

struct ContentView: View {
    @StateObject private var lm = LocationManager()
    
    // Persisted toggles
    @AppStorage("useFeet") private var useFeet = false

    // Time mode: "UTC" or "Local"
    @AppStorage("timeMode") private var timeModeRaw: String = Maff.TimeMode.utc.rawValue
    private var timeMode: Maff.TimeMode {
        get { Maff.TimeMode(rawValue: timeModeRaw) ?? .utc }
        set { timeModeRaw = newValue.rawValue }
    }
    
    // Flash banner (top-right)
    @State private var flash: String? = nil
    @State private var flashTask: DispatchWorkItem? = nil   // cancel/replace banner timers
    
    var body: some View {
        TabView {
            // === Readout Tab ===
            NavigationView {
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        header
                        telemetryCard
                        toggles
                        
                        // === Single row: three equal-width buttons ===
                        HStack(spacing: 8) {
                            Button {
                                lm.resetAGLToCurrentAltitude()
                                flashCopied("AGL Reset")
                            } label: {
                                labelButton("Reset AGL Ref")
                            }
                            .frame(maxWidth: .infinity)
                            
                            Button {
                                UIPasteboard.general.string = simpleCoordsString()
                                flashCopied("Copied Coordinates")
                            } label: {
                                labelButton("Copy Coordinates")
                            }
                            .frame(maxWidth: .infinity)
                            
                            Button {
                                UIPasteboard.general.string = fullInfoString()
                                flashCopied("Copied Full Info")
                            } label: {
                                labelButton("Copy Full Info")
                            }
                            .frame(maxWidth: .infinity)
                        }
                        .padding(.top, 2)
                    }
                    .padding()
                    .mono10() // apply mono theme to the whole screen
                }
                // Using a custom header; keep nav bar title empty
                .navigationTitle("")
                .navigationBarTitleDisplayMode(.inline)
            }
            .onAppear { lm.start() }
            // === Flash banner: top-right ===
            .overlay(alignment: .topTrailing) {
                if let msg = flash {
                    Text(msg)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(.ultraThinMaterial, in: Capsule())
                        .overlay(Capsule().stroke(.secondary.opacity(0.3)))
                        .padding(.top, 10)
                        .padding(.trailing, 12)
                        .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }
            .animation(.easeInOut(duration: 0.25), value: flash)
            .tabItem {
                Label("Readout", systemImage: "list.bullet.rectangle")
            }

            // === Map Manager Tab ===
            MapManager(lm: lm)
                .tabItem {
                    Label("Map", systemImage: "map")
                }
        }
        // enforce mono across the app
        .environment(\.font, AppTheme.baseFont)
    }
    
    // MARK: - UI pieces
    
    private var header: some View {
        HStack(spacing: 8) {
            Image("Icon-DEV")
                .resizable()
                .scaledToFit()
                .frame(width: 22, height: 22)
                .clipShape(RoundedRectangle(cornerRadius: 4))
                .overlay(RoundedRectangle(cornerRadius: 4).stroke(.secondary.opacity(0.3), lineWidth: 0.5))
            
            Text("GNSS Toolkit")
                .monoTitle()
            
            Spacer()
        }
        .padding(.bottom, 2)
    }
    
    private var telemetryCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            telemetryRow(label: "Latitude",  value: latText)
            telemetryRow(label: "Longitude", value: lonText)
            telemetryRow(label: "Altitude (MSL)", value: altitudeMSLText)
            telemetryRow(label: "Altitude (AGL)", value: altitudeAGLText)
            telemetryRow(label: "Speed (Instant)", value: speedInstantText)
            telemetryRow(label: "Speed (Avg 10s)", value: speedAvgText)
            telemetryRow(label: "Time", value: timeText)
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(.thinMaterial)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(.secondary.opacity(0.15), lineWidth: 1)
        )
    }
    
    private func telemetryRow(label: String, value: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label).foregroundStyle(.secondary)
            Spacer(minLength: 8)
            Text(value)
        }
        .padding(.vertical, 2)
    }
    
    private var toggles: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Display Options")
                .foregroundStyle(.secondary)
                .mono10()
            HStack {
                Picker("Units", selection: $useFeet) {
                    Text("Meters").mono10().tag(false)
                    Text("Feet").mono10().tag(true)
                }
                .pickerStyle(.segmented)
                
                Picker("Time", selection: $timeModeRaw) {
                    Text("UTC").mono10().tag(Maff.TimeMode.utc.rawValue)
                    Text("Local").mono10().tag(Maff.TimeMode.local.rawValue)
                }
                .pickerStyle(.segmented)
            }
        }
        .padding(.top, 6)
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
    
    // MARK: - Flash banner helper
    
    private func flashCopied(_ message: String, seconds: Double = 3.0) {
        flashTask?.cancel()
        flash = message
        let work = DispatchWorkItem { withAnimation { self.flash = nil } }
        flashTask = work
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds, execute: work)
    }
    
    // MARK: - Text builders (use Maff)
    private var latText: String {
        if let v = lm.latitude { return String(format: "%.6f", v) }
        return "--"
    }
    private var lonText: String {
        if let v = lm.longitude { return String(format: "%.6f", v) }
        return "--"
    }
    private var altitudeMSLText: String { Maff.distanceText(fromMeters: lm.altitudeMSL, useFeet: useFeet) }
    private var altitudeAGLText: String { Maff.distanceText(fromMeters: lm.altitudeAGL, useFeet: useFeet) }
    private var speedInstantText: String { Maff.speedText(fromMS: lm.speedInstantMS, useFeet: useFeet) }
    private var speedAvgText: String { Maff.speedText(fromMS: lm.speedAvg10sMS, useFeet: useFeet) }
    private var timeText: String {
        Maff.timeText(date: lm.lastFix, mode: timeMode)
    }
    
    private func simpleCoordsString() -> String {
        Maff.coordsText(lat: lm.latitude, lon: lm.longitude)
    }
    
    private func fullInfoString() -> String {
        let msl  = Maff.distanceText(fromMeters: lm.altitudeMSL, useFeet: useFeet)
        let agl  = Maff.distanceText(fromMeters: lm.altitudeAGL, useFeet: useFeet)
        let spI  = Maff.speedText(fromMS: lm.speedInstantMS, useFeet: useFeet)
        let spA  = Maff.speedText(fromMS: lm.speedAvg10sMS, useFeet: useFeet)
        let time = Maff.timeText(date: lm.lastFix, mode: timeMode)

        return """
        Latitude: \(latText)
        Longitude: \(lonText)
        Alt MSL: \(msl)
        Alt AGL: \(agl)
        Speed (Instant): \(spI)
        Speed (Avg 10s): \(spA)
        Time: \(time)
        """
    }
}
