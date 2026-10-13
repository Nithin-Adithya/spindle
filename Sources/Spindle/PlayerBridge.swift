import AppKit

enum PlayerSource: String, CaseIterable {
    case music, spotify

    var bundleID: String {
        switch self {
        case .music: return "com.apple.Music"
        case .spotify: return "com.spotify.client"
        }
    }

    var appName: String {
        switch self {
        case .music: return "Music"
        case .spotify: return "Spotify"
        }
    }

    /// Broadcasts the player sends when its track or play state changes.
    var notificationNames: [String] {
        switch self {
        case .music: return ["com.apple.Music.playerInfo", "com.apple.iTunes.playerInfo"]
        case .spotify: return ["com.spotify.client.PlaybackStateChanged"]
        }
    }

    var isRunning: Bool {
        !NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).isEmpty
    }
}

struct Track: Equatable {
    var source: PlayerSource
    var id: String
    var title: String
    var artist: String
    var album: String
    var duration: Double
    var artworkURL: URL?
}

struct PlayerSnapshot {
    var source: PlayerSource
    var isPlaying: Bool
    var position: Double
    var track: Track?
}

/// Talks to Music and Spotify through AppleScript. Every call must come from
/// `PlayerBridge.queue`: NSAppleScript is not thread-safe.
final class PlayerBridge {
    static let queue = DispatchQueue(label: "spindle.applescript")

    private var compiled: [String: NSAppleScript] = [:]

    private func run(_ source: String, cache: Bool = true) -> NSAppleEventDescriptor? {
        let script: NSAppleScript
        if let hit = compiled[source] {
            script = hit
        } else {
            guard let fresh = NSAppleScript(source: source) else { return nil }
            if cache { compiled[source] = fresh }
            script = fresh
        }
        var error: NSDictionary?
        let result = script.executeAndReturnError(&error)
        return error == nil ? result : nil
    }

    func snapshot(of source: PlayerSource) -> PlayerSnapshot? {
        // Asking a closed app for its state would launch it.
        guard source.isRunning else { return nil }

        let fields: String
        switch source {
        case .music:
            fields = "{s, name of t, artist of t, album of t, duration of t, player position, (database ID of t) as text}"
        case .spotify:
            fields = "{s, name of t, artist of t, album of t, (duration of t) / 1000, player position, id of t, artwork url of t}"
        }
        let script = """
        tell application "\(source.appName)"
            set s to player state as text
            try
                set t to current track
                return \(fields)
            on error
                return {s}
            end try
        end tell
        """
        guard let result = run(script), result.numberOfItems >= 1 else { return nil }

        func text(_ index: Int) -> String { result.atIndex(index)?.stringValue ?? "" }
        func number(_ index: Int) -> Double { result.atIndex(index)?.doubleValue ?? 0 }

        let isPlaying = text(1) == "playing"
        guard result.numberOfItems >= 7 else {
            return PlayerSnapshot(source: source, isPlaying: isPlaying, position: 0, track: nil)
        }
        let track = Track(
            source: source,
            id: text(7),
            title: text(2),
            artist: text(3),
            album: text(4),
            duration: number(5),
            artworkURL: result.numberOfItems >= 8 ? URL(string: text(8)) : nil
        )
        return PlayerSnapshot(source: source, isPlaying: isPlaying, position: number(6), track: track)
    }

    /// Music hands artwork over as raw image data; Spotify only gives a URL.
    func musicArtwork() -> NSImage? {
        guard PlayerSource.music.isRunning,
              let result = run("tell application \"Music\" to get data of artwork 1 of current track")
        else { return nil }
        return NSImage(data: result.data)
    }

    func playPause(_ source: PlayerSource) { command("playpause", source) }
    func pause(_ source: PlayerSource) { command("pause", source) }
    func next(_ source: PlayerSource) { command("next track", source) }
    func previous(_ source: PlayerSource) { command("previous track", source) }

    func seek(_ source: PlayerSource, to seconds: Double) {
        guard source.isRunning else { return }
        _ = run("tell application \"\(source.appName)\" to set player position to \(Int(seconds))", cache: false)
    }

    private func command(_ verb: String, _ source: PlayerSource) {
        guard source.isRunning else { return }
        _ = run("tell application \"\(source.appName)\" to \(verb)")
    }
}
