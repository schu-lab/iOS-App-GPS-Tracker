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
    @AppStorage("useUTC") private var useUTC = true
    
    // Ephemeral “Copied!” banner
    @State private var flash: String? = nil
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    header
                    
                    telemetryCard
                    
                    toggles
                    
                    HStack(spacing: 12) {
                        Button(role: .none) {
                            lm.resetAGLToCurrentAltitude()
                        } label: {
                            labelButton("Reset AGL Ground")
                        }
                        
                        Button {
                            UIPasteboard.general.string = simpleCoordsString()
                            flashCopied("Copied coords")
                        } label: {
                            labelButton("Copy Coords")
                        }
                    }
                    
                    Button {
                        UIPasteboard.general.string = fullInfoString()
                        flashCopied("Copied full info")
                    } label: {
                        labelButton("Copy Full Info")
                            .frame(maxWidth: .infinity)
                    }
                    .padding(.top, 2)
                }
                .padding()
                .mono10()
            }
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
        }
        .onAppear { lm.start() }
        .overlay(alignment: .top) {
            if let msg = flash {
                Text(msg)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(.ultraThinMaterial, in: Capsule())
                    .overlay(Capsule().stroke(.secondary.opacity(0.3)))
                    .padding(.top, 10)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .animation(.easeInOut(duration: 0.25), value: flash)
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
            Text("Display Options").foregroundStyle(.secondary)
            HStack {
                Picker("Units", selection: $useFeet) {
                    Text("Meters").tag(false)
                    Text("Feet").tag(true)
                }
                .pickerStyle(.segmented)
                
                Picker("Time", selection: $useUTC) {
                    Text("UTC").tag(true)
                    Text("Local").tag(false)
                }
                .pickerStyle(.segmented)
            }
        }
        .padding(.top, 6)
    }
    
    private func labelButton(_ title: String) -> some View {
        Text(title)
            .mono10()
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(.thinMaterial, in: Capsule())
            .overlay(Capsule().stroke(.secondary.opacity(0.25)))
    }
    
    private func flashCopied(_ message: String) {
        flash = message
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
            withAnimation { flash = nil }
        }
    }
    
    // MARK: - Text builders (now call Maff)
    private var latText: String {
        Maff.coordsText(lat: lm.latitude, lon: lm.longitude).split(separator: ",").first.map(String.init) ?? "--"
    }
    private var lonText: String {
        Maff.coordsText(lat: lm.latitude, lon: lm.longitude).split(separator: ",").last.map { $0.trimmingCharacters(in: .whitespaces) } ?? "--"
    }
    private var altitudeMSLText: String {
        Maff.distanceText(fromMeters: lm.altitudeMSL, useFeet: useFeet)
    }
    private var altitudeAGLText: String {
        Maff.distanceText(fromMeters: lm.altitudeAGL, useFeet: useFeet)
    }
    private var speedInstantText: String {
        Maff.speedText(fromMS: lm.speedInstantMS, useFeet: useFeet)
    }
    private var speedAvgText: String {
        Maff.speedText(fromMS: lm.speedAvg10sMS, useFeet: useFeet)
    }
    private var timeText: String {
        guard let t = lm.lastFix else { return "--" }
        return formattedTime(t)
    }
    
    private func formattedTime(_ date: Date) -> String {
        if useUTC {
            let df = ISO8601DateFormatter()
            df.timeZone = TimeZone(secondsFromGMT: 0)
            df.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            return df.string(from: date)
        } else {
            let df = DateFormatter()
            df.dateStyle = .medium
            df.timeStyle = .medium
            df.timeZone = .current
            return df.string(from: date)
        }
    }
    
    private func simpleCoordsString() -> String {
        Maff.coordsText(lat: lm.latitude, lon: lm.longitude)
    }
    
    private func fullInfoString() -> String {
        let latlon = Maff.coordsText(lat: lm.latitude, lon: lm.longitude)
        let msl = Maff.distanceText(fromMeters: lm.altitudeMSL, useFeet: useFeet)
        let agl = Maff.distanceText(fromMeters: lm.altitudeAGL, useFeet: useFeet)
        let spI = Maff.speedText(fromMS: lm.speedInstantMS, useFeet: useFeet)
        let spA = Maff.speedText(fromMS: lm.speedAvg10sMS, useFeet: useFeet)
        let time = lm.lastFix.map { formattedTime($0) } ?? "--"
        return "Lat/Lon: \(latlon), Alt MSL: \(msl), Alt AGL: \(agl), Speed: \(spI) (avg10s \(spA)), Time: \(time)"
    }
}
