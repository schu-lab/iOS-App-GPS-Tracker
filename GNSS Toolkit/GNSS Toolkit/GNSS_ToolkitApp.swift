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
        // Force segmented pickers to use the mono font globally
        AppTheme.applyAppearance()
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                // optional: enforce mono across the app
                .environment(\.font, AppTheme.baseFont)
        }
    }
}
