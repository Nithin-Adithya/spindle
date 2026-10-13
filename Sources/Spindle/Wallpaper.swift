import AppKit

/// Sets the current cover as the desktop picture, and puts the user's own
/// pictures back when the feature is turned off or the app quits.
final class WallpaperManager {
    private let originalsKey = "wallpaperOriginals"
    private var active: Bool { UserDefaults.standard.dictionary(forKey: originalsKey) != nil }

    private var folder: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("Spindle/Wallpaper", isDirectory: true)
    }

    func update(enabled: Bool, allDisplays: Bool, artwork: NSImage?, trackID: String?) {
        guard enabled else { return restore() }
        guard let artwork, let trackID, let data = artwork.tiffRepresentation,
              let png = NSBitmapImageRep(data: data)?.representation(using: .png, properties: [:]) else { return }

        if !active {
            // Remember what each display showed before touching anything.
            var originals: [String: String] = [:]
            for screen in NSScreen.screens {
                if let url = NSWorkspace.shared.desktopImageURL(for: screen) { originals[Self.key(screen)] = url.path }
            }
            UserDefaults.standard.set(originals, forKey: originalsKey)
        }

        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        // The system caches desktop pictures by path, so each cover needs its own file name.
        let safeID = trackID.replacingOccurrences(of: "[^A-Za-z0-9]", with: "_", options: .regularExpression)
        let file = folder.appendingPathComponent(safeID + ".png")
        (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil))?
            .filter { $0 != file }.forEach { try? FileManager.default.removeItem(at: $0) }
        guard (try? png.write(to: file)) != nil else { return }

        let options: [NSWorkspace.DesktopImageOptionKey: Any] = [
            .imageScaling: NSImageScaling.scaleProportionallyUpOrDown.rawValue,
            .allowClipping: true,
        ]
        for (index, screen) in NSScreen.screens.enumerated() {
            if allDisplays || index == 0 {
                try? NSWorkspace.shared.setDesktopImageURL(file, for: screen, options: options)
            } else if let path = (UserDefaults.standard.dictionary(forKey: originalsKey) as? [String: String])?[Self.key(screen)] {
                // A display that is no longer included gets its own picture back.
                try? NSWorkspace.shared.setDesktopImageURL(URL(fileURLWithPath: path), for: screen, options: [:])
            }
        }
    }

    func restore() {
        guard let originals = UserDefaults.standard.dictionary(forKey: originalsKey) as? [String: String] else { return }
        for screen in NSScreen.screens {
            if let path = originals[Self.key(screen)] {
                try? NSWorkspace.shared.setDesktopImageURL(URL(fileURLWithPath: path), for: screen, options: [:])
            }
        }
        UserDefaults.standard.removeObject(forKey: originalsKey)
        try? FileManager.default.removeItem(at: folder)
    }

    private static func key(_ screen: NSScreen) -> String {
        "\(screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] ?? 0)"
    }
}
