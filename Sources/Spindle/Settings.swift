import SwiftUI

/// Right-to-left when the app is running in Arabic. The app is assembled by hand
/// rather than by Xcode, and AppKit does not pick this up from the bundle here.
let appLayoutDirection: LayoutDirection = {
    let language = Locale.Language(identifier: Bundle.main.preferredLocalizations.first ?? "en")
    return language.characterDirection == .rightToLeft ? .rightToLeft : .leftToRight
}()

/// Looks a string up in the app's translations; the English text is the key.
func L(_ key: String) -> String { NSLocalizedString(key, comment: "") }

/// Every preference, stored in UserDefaults. Views bind to these directly; the
/// app delegate re-applies windows, shortcuts and Dock state whenever one changes.
final class Settings: ObservableObject {
    static let shared = Settings()

    /// Set by the app delegate; opens the settings window.
    var openWindow: () -> Void = {}

    // General
    @AppStorage("showMenuBarIcon") var showMenuBarIcon = true
    @AppStorage("showDockIcon") var showDockIcon = false
    @AppStorage("artworkInDock") var artworkInDock = false
    @AppStorage("source") var source = SourcePreference.automatic
    @AppStorage("useAlbumColor") var useAlbumColor = true

    // Notch
    @AppStorage("showNotch") var showNotch = false
    @AppStorage("notchStyle") var notchStyle = NotchStyle.black
    @AppStorage("hideNotchInFullScreen") var hideNotchInFullScreen = true

    // Desktop widget
    @AppStorage("showWidget") var showWidget = false
    @AppStorage("widgetLevel") var widgetLevel = WidgetLevel.normal
    @AppStorage("widgetTheme") var widgetTheme = WidgetTheme.sleeve
    @AppStorage("widgetSize") var widgetSize = WidgetSize.medium
    @AppStorage("widgetBackground") var widgetBackground = WidgetBackground.album
    @AppStorage("widgetColor") var widgetColor = "#2A2A2E"
    @AppStorage("widgetImagePath") var widgetImagePath = ""
    @AppStorage("widgetTitleColor") var widgetTitleColor = "#FFFFFF"
    @AppStorage("widgetFont") var widgetFont = WidgetFont.standard
    @AppStorage("widgetStylus") var widgetStylus = true
    @AppStorage("widgetProgress") var widgetProgress = true
    @AppStorage("widgetShadow") var widgetShadow = true
    @AppStorage("coverAsWallpaper") var coverAsWallpaper = false
}

enum WidgetTheme: String, CaseIterable, Identifiable {
    case sleeve, turntable, compact

    var id: String { rawValue }

    var label: String {
        switch self {
        case .sleeve: return L("Sleeve")
        case .turntable: return L("Turntable")
        case .compact: return L("Compact")
        }
    }

    var detail: String {
        switch self {
        case .sleeve: return L("The cover as a record sleeve with the record sliding out beside it.")
        case .turntable: return L("A full record on a deck with the tonearm, track details underneath.")
        case .compact: return L("A small bar with the cover, track details and controls. No record.")
        }
    }

    /// Layout size before the size setting scales it.
    var baseSize: CGSize {
        switch self {
        case .sleeve: return CGSize(width: 456, height: 186)
        case .turntable: return CGSize(width: 250, height: 372)
        case .compact: return CGSize(width: 360, height: 104)
        }
    }
}

enum WidgetSize: String, CaseIterable, Identifiable {
    case small, medium, large, extraLarge

    var id: String { rawValue }

    var label: String {
        switch self {
        case .small: return L("Small")
        case .medium: return L("Medium")
        case .large: return L("Large")
        case .extraLarge: return L("Extra large")
        }
    }

    var scale: Double {
        switch self {
        case .small: return 0.75
        case .medium: return 1
        case .large: return 1.3
        case .extraLarge: return 1.65
        }
    }
}

enum WidgetBackground: String, CaseIterable, Identifiable {
    case album, cover, color, image, transparent

    var id: String { rawValue }

    var label: String {
        switch self {
        case .album: return L("Album color")
        case .cover: return L("Album cover")
        case .color: return L("Custom color")
        case .image: return L("Custom image")
        case .transparent: return L("Transparent")
        }
    }
}

enum WidgetFont: String, CaseIterable, Identifiable {
    case standard, rounded, serif, monospaced

    var id: String { rawValue }

    var label: String {
        switch self {
        case .standard: return L("Standard")
        case .rounded: return L("Rounded")
        case .serif: return L("Serif")
        case .monospaced: return L("Monospaced")
        }
    }

    var design: Font.Design {
        switch self {
        case .standard: return .default
        case .rounded: return .rounded
        case .serif: return .serif
        case .monospaced: return .monospaced
        }
    }
}

extension Color {
    /// "#RRGGBB"; anything unreadable comes back as white.
    init(hex: String) {
        let value = UInt32(hex.trimmingCharacters(in: CharacterSet(charactersIn: "#")), radix: 16) ?? 0xFFFFFF
        self.init(.sRGB, red: Double((value >> 16) & 0xFF) / 255, green: Double((value >> 8) & 0xFF) / 255,
                  blue: Double(value & 0xFF) / 255)
    }

    var hex: String {
        let color = NSColor(self).usingColorSpace(.sRGB) ?? .white
        return String(format: "#%02X%02X%02X", Int((color.redComponent * 255).rounded()),
                      Int((color.greenComponent * 255).rounded()), Int((color.blueComponent * 255).rounded()))
    }
}

enum SourcePreference: String, CaseIterable, Identifiable {
    case automatic, music, spotify

    var id: String { rawValue }

    var label: String {
        switch self {
        case .automatic: return L("Automatic")
        case .music: return "Apple Music"
        case .spotify: return "Spotify"
        }
    }

    var sources: [PlayerSource] {
        switch self {
        case .automatic: return PlayerSource.allCases
        case .music: return [.music]
        case .spotify: return [.spotify]
        }
    }
}

enum WidgetLevel: String, CaseIterable, Identifiable {
    case below, normal, front

    var id: String { rawValue }

    var label: String {
        switch self {
        case .below: return L("Below all windows")
        case .normal: return L("Like a normal window")
        case .front: return L("Above all windows")
        }
    }

    var windowLevel: NSWindow.Level {
        switch self {
        case .below: return NSWindow.Level(Int(CGWindowLevelForKey(.desktopIconWindow)) + 1)
        case .normal: return .normal
        case .front: return .floating
        }
    }
}

enum NotchStyle: String, CaseIterable, Identifiable {
    case black, glass, glassLight, glassDark

    var id: String { rawValue }

    var label: String {
        switch self {
        case .black: return L("Black")
        case .glass: return L("Glass (match system)")
        case .glassLight: return L("Glass, light")
        case .glassDark: return L("Glass, dark")
        }
    }

    var detail: String {
        switch self {
        case .black: return L("The original solid pill.")
        case .glass: return L("Dark glass in Dark Mode, light glass in Light Mode.")
        case .glassLight: return L("Always light, with black text and controls.")
        case .glassDark: return L("Always dark, with white text and controls.")
        }
    }

    /// Liquid Glass needs macOS 26; older systems only get the black pill.
    static var available: [NotchStyle] {
        if #available(macOS 26.0, *) { return allCases }
        return [.black]
    }
}
