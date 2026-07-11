//
//  ThemeManager.swift
//  llama Mail
//
//  Holds the active theme and persists the selection in UserDefaults
//  (spec §1: theme name is non-sensitive). Injected into the SwiftUI
//  environment so every view re-renders on theme change.
//

import SwiftUI
import Observation

@Observable
@MainActor
final class ThemeManager {
    private static let storageKey = "theme.selectedName"

    private let defaults: UserDefaults

    private(set) var themeName: String
    private(set) var palette: ThemePalette

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let saved = defaults.string(forKey: Self.storageKey) ?? AppTheme.defaultThemeName
        let name = AppTheme.palettes[saved] != nil ? saved : AppTheme.defaultThemeName
        themeName = name
        palette = AppTheme.palette(named: name)
    }

    func setTheme(named name: String) {
        guard AppTheme.palettes[name] != nil else { return }
        themeName = name
        palette = AppTheme.palette(named: name)
        defaults.set(name, forKey: Self.storageKey)
    }
}

extension EnvironmentValues {
    /// The active palette; defaults to Dark Matter until the app injects one.
    @Entry var theme: ThemePalette = AppTheme.palette(named: AppTheme.defaultThemeName)
}

// MARK: - Typography (STYLE_GUIDE §2)

/// ponytail: Space Grotesk / IBM Plex Mono should ship as bundled fonts in v2
/// (iOS has no Google Fonts provider like Android). Until the TTFs are added
/// to the bundle these resolve to the system font, which the style guide
/// accepts ("stay native wins"); the custom names are tried first so dropping
/// the fonts in later requires no code change.
enum AppFont {
    static func ui(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        custom("Space Grotesk", size: size, weight: weight, fallbackDesign: .default)
    }

    static func mono(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        custom("IBM Plex Mono", size: size, weight: weight, fallbackDesign: .monospaced)
    }

    private static func custom(
        _ name: String,
        size: CGFloat,
        weight: Font.Weight,
        fallbackDesign: Font.Design
    ) -> Font {
        if isFontAvailable(name) {
            return .custom(name, size: size).weight(weight)
        }
        return .system(size: size, weight: weight, design: fallbackDesign)
    }

    private static func isFontAvailable(_ name: String) -> Bool {
#if canImport(UIKit)
        UIFont(name: name, size: 12) != nil
#elseif canImport(AppKit)
        NSFont(name: name, size: 12) != nil
#else
        false
#endif
    }
}

#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif
