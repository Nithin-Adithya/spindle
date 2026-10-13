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
    var volume: Double
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
            fields = "{s, v, name of t, artist of t, album of t, duration of t, player position, (database ID of t) as text}"
        case .spotify:
            fields = "{s, v, name of t, artist of t, album of t, (duration of t) / 1000, player position, id of t, artwork url of t}"
        }
        let script = """
        tell application "\(source.appName)"
            set s to player state as text
            set v to sound volume
            try
                set t to current track
                return \(fields)
            on error
                return {s, v}
            end try
        end tell
        """
        guard let result = run(script), result.numberOfItems >= 2 else { return nil }

        func text(_ index: Int) -> String { result.atIndex(index)?.stringValue ?? "" }
        func number(_ index: Int) -> Double { result.atIndex(index)?.doubleValue ?? 0 }

        let isPlaying = text(1) == "playing"
        let volume = number(2)
        guard result.numberOfItems >= 8 else {
            return PlayerSnapshot(source: source, isPlaying: isPlaying, position: 0, volume: volume, track: nil)
        }
        let track = Track(
            source: source,
            id: text(8),
            title: text(3),
            artist: text(4),
            album: text(5),
            duration: number(6),
            artworkURL: result.numberOfItems >= 9 ? URL(string: text(9)) : nil
        )
        return PlayerSnapshot(source: source, isPlaying: isPlaying, position: number(7), volume: volume, track: track)
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

    func setVolume(_ source: PlayerSource, to volume: Double) {
        guard source.isRunning else { return }
        _ = run("tell application \"\(source.appName)\" to set sound volume to \(Int(volume))", cache: false)
    }

    private func command(_ verb: String, _ source: PlayerSource) {
        guard source.isRunning else { return }
        _ = run("tell application \"\(source.appName)\" to \(verb)")
    }
}
