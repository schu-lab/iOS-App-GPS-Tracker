//
//  GNSS_ToolkitApp.swift
//  GNSS Toolkit
//
//  Created by Simon Chu on 9/1/25.
//

import SwiftUI

@main
struct GNSS_ToolkitApp: App {
    init() {
        // Apply global UIKit appearances (segmented controls, etc.)
        AppTheme.applyAppearance()
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                // Enforce mono across all SwiftUI views
                .environment(\.font, AppTheme.baseFont)
        }
    }
}
