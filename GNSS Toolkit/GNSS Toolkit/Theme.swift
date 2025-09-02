//
//  Theme.swift
//  GNSS Toolkit
//
//  Created by Simon Chu on 9/1/25.
//

import SwiftUI
import UIKit   // <- needed for UIFont / appearance

enum AppTheme {
    static let baseFontSize: CGFloat = 10

    // SwiftUI fonts
    static var baseFont: Font {
        .system(size: baseFontSize, design: .monospaced).monospacedDigit()
    }
    static var titleFont: Font {
        .system(size: 18, design: .monospaced).weight(.bold)
    }

    // UIKit fonts (for appearance proxies)
    static var baseUIFont: UIFont {
        .monospacedSystemFont(ofSize: baseFontSize, weight: .regular)
    }
    static var baseUIFontBold: UIFont {
        .monospacedSystemFont(ofSize: baseFontSize, weight: .bold)
    }

    /// Apply global UIKit appearances that SwiftUI doesn't expose (e.g., segmented picker font)
    static func applyAppearance() {
        let normalAttrs: [NSAttributedString.Key: Any] = [.font: baseUIFont]
        let selectedAttrs: [NSAttributedString.Key: Any] = [.font: baseUIFontBold]

        let segmented = UISegmentedControl.appearance()
        segmented.setTitleTextAttributes(normalAttrs, for: .normal)
        segmented.setTitleTextAttributes(selectedAttrs, for: .selected)
    }
}

/// Apply the app’s default mono font (10 pt monospaced)
struct Mono10: ViewModifier {
    func body(content: Content) -> some View {
        content.font(AppTheme.baseFont)
    }
}
struct MonoTitle: ViewModifier {
    func body(content: Content) -> some View {
        content.font(AppTheme.titleFont)
    }
}

extension View {
    func mono10() -> some View { modifier(Mono10()) }
    func monoTitle() -> some View { modifier(MonoTitle()) }
}
