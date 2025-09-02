# 📍 GNSS Toolkit (iOS)

An experimental iOS application for **GNSS tracking, mapping, and geofencing** — built with **SwiftUI**, **CoreLocation**, and **MapKit**.  

This toolkit provides precise readouts, intuitive map overlays, and quick-access field tools for navigation and situational awareness.  

⚠️ **Note:** This project is still in active development and not yet released.

---

## ✨ Major Pages

### 🔢 Readout
- Live telemetry:
  - Latitude / Longitude
  - Altitude (MSL & AGL)
  - Speed (instant + 10s rolling average)
  - Timestamp (UTC or Local)
- Toggle display units (**meters/feet**) and **time modes** (**UTC/Local**).
- Quick actions:
  - Reset AGL reference  
  - Copy current coordinates  
  - Copy full readout  

---

### 🗺 Map Manager
- Full-screen interactive map with:
  - Origin, Target, and Me annotations  
  - Bearing/distance overlays (Origin → Target, Origin → Me, Me → Target)  
  - Geofence outline (red, no fill)  
- HUD tabs for:
  - **Controls** → set/clear origin & target, enter coordinates, copy 15-field “Map Info” snapshot  
  - **Geofence** → radius input, one-tap presets (100m → 50km), signed inside/outside offsets  
  - **Origin / Target** → details with position, altitude, timestamp, and relative distances  

---

### 📐 Utilities (Maff)
- Distance & speed conversions:
  - meters ↔ feet  
  - m/s ↔ ft/s  
- Rolling mean for speed smoothing  
- Friendly timestamp formatting:
  - Forced `UTC` literal
  - Local with zone abbreviation  
- AGL (Above Ground Level) baseline helpers  

---

### 🎨 Theme
- Global **monospaced font** styling (10 pt for readout, bold titles for HUD)  
- UIKit appearance overrides for segmented pickers  

---

## 🚧 Status
This project is **work in progress** — not yet released on the App Store.  
Expect frequent refactors, feature additions, and UI experiments.

---

## 📌 Roadmap
- [ ] Map snapshot export with overlays  
- [ ] iPad multitasking layout  
- [ ] GPX import/export  
- [ ] Dark mode map themes  
- [ ] Multi-geofence support  

---

## 🛠 Development

### Requirements
- iOS 17+  
- Xcode 15+  
- Swift 5.9+  

### Run
```bash
git clone https://github.com/schu-lab/iOS-App-GPS-Tracker.git
cd iOS-App-GPS-Tracker
open GNSS_ToolkitApp.swift
```

![Readout Screenshot](docs/screenshots/readout.png)
![Map Manager Screenshot](docs/screenshots/map.png)


