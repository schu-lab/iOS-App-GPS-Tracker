//
//  Theme.swift
//  GNSS Toolkit
//
//  Created by Simon Chu on 9/1/25.
//
import SwiftUI

enum AppTheme {
    static let baseFontSize: CGFloat = 10
    static let titleFontSize: CGFloat = 18   // tweak size as you like

    // Body font (monospaced)
    static var baseFont: Font {
        .system(size: baseFontSize, design: .monospaced)
            .monospacedDigit()
    }

    // Title font (monospaced, bold)
    static var titleFont: Font {
        .system(size: titleFontSize, design: .monospaced)
            .weight(.bold)
    }
}

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
