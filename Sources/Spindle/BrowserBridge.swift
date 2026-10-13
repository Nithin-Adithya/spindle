import AppKit

/// Reads and controls music playing in a browser tab by running a small script
/// in the page through AppleScript. Each browser has to have "Allow JavaScript
/// from Apple Events" turned on (Develop menu in Safari, View > Developer in
/// Chrome-family browsers). Call only from `PlayerBridge.queue`.
final class BrowserBridge {
    struct Browser {
        let name: String
        let bundleID: String
        /// Safari and Chrome-family browsers spell the same commands differently.
        let isSafari: Bool

        var isRunning: Bool { !NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).isEmpty }
    }

    static let browsers = [
        Browser(name: "Safari", bundleID: "com.apple.Safari", isSafari: true),
        Browser(name: "Google Chrome", bundleID: "com.google.Chrome", isSafari: false),
        Browser(name: "Brave Browser", bundleID: "com.brave.Browser", isSafari: false),
        Browser(name: "Microsoft Edge", bundleID: "com.microsoft.edgemac", isSafari: false),
        Browser(name: "Arc", bundleID: "company.thebrowser.Browser", isSafari: false),
    ]

    static var anyRunning: Bool { browsers.contains(where: \.isRunning) }

    /// Only tabs on these sites are touched.
    private static let hosts = [
        "music.youtube.com", "youtube.com", "open.spotify.com", "music.apple.com", "music.amazon.", "tidal.com",
        "soundcloud.com", "deezer.com", "pandora.com", "qobuz.com", "mixcloud.com", "music.yandex.",
    ]

    private struct Target: Equatable {
        let browser: String
        let isSafari: Bool
        let window: Int
        let tab: Int
    }

    // Browser scripts run in a separate `osascript` process on their own queue. A browser
    // that is waiting for the user to answer a permission prompt holds its script for as
    // long as that takes, and that must never stall the Spotify and Music polling.
    private let queue = DispatchQueue(label: "spindle.browser")
    private let lock = NSLock()
    private var latest: PlayerSnapshot?
    private var blockedNames: Set<String> = []
    private var refreshing = false

    // Touched only on `queue`.
    private var target: Target?
    private var tabs: [Target] = []
    private var tabsListed = Date.distantPast

    /// Browsers that refused to run the script; shown to the user as a setting to turn on.
    var blocked: Set<String> {
        lock.lock()
        defer { lock.unlock() }
        return blockedNames
    }

    // MARK: Page scripts (single-quoted so they drop into an AppleScript string)

    private static let find = "var m=document.querySelector('video,audio');"
    private static let readScript = """
    (function(){\(find)var s=navigator.mediaSession&&navigator.mediaSession.metadata;if(!m&&!s)return '';\
    var w=s&&s.artwork&&s.artwork.length?s.artwork[s.artwork.length-1].src:'';\
    var p=m?!m.paused:(navigator.mediaSession.playbackState=='playing');\
    return JSON.stringify({t:s&&s.title?s.title:document.title,a:s?s.artist:'',l:s?s.album:'',w:w,p:p,\
    c:m?m.currentTime:0,d:m&&isFinite(m.duration)?m.duration:0,v:m?Math.round(m.volume*100):100});})()
    """

    /// Clicks the first of the site's own buttons that exists; used where the media element can't do the job.
    private static func click(_ selectors: [String]) -> String {
        let list = selectors.map { "'\($0)'" }.joined(separator: ",")
        return "(function(){var q=[\(list)];for(var i=0;i<q.length;i++){var b=document.querySelector(q[i]);if(b){b.click();return 1;}}return 0;})()"
    }

    private static let playPauseScript = """
    (function(){\(find)if(m&&isFinite(m.duration)&&m.duration>0){if(m.paused)m.play();else m.pause();return 1;}\
    return \(click(["[data-testid=control-button-playpause]", "#play-pause-button", ".playControl", ".ytp-play-button"]));})()
    """
    private static let nextScript = click([
        "ytmusic-player-bar .next-button", "[data-testid=control-button-skip-forward]", ".skipControl__next",
        ".ytp-next-button", "[data-test=next]", "button[aria-label*=Next]",
    ])
    private static let previousScript = click([
        "ytmusic-player-bar .previous-button", "[data-testid=control-button-skip-back]", ".skipControl__previous",
        ".ytp-prev-button", "[data-test=previous]", "button[aria-label*=Previous]",
    ])

    // MARK: Reading

    /// The most recent reading. Returns at once and starts the next reading in the background.
    func snapshot() -> PlayerSnapshot? {
        lock.lock()
        let value = latest
        let start = !refreshing
        if start { refreshing = true }
        lock.unlock()
        if start {
            queue.async {
                let fresh = self.read()
                self.lock.lock()
                self.latest = fresh
                self.refreshing = false
                self.lock.unlock()
            }
        }
        return value
    }

    private func read() -> PlayerSnapshot? {
        // Tabs come and go slowly; listing them every few seconds is enough.
        if Date().timeIntervalSince(tabsListed) > 3 {
            tabs = Self.browsers.filter(\.isRunning).flatMap(musicTabs)
            tabsListed = Date()
        }
        var paused: (Target, PlayerSnapshot)?
        for group in Dictionary(grouping: tabs, by: \.browser).values {
            let results = evaluate(Self.readScript, in: group)
            for (candidate, json) in zip(group, results) {
                guard let snapshot = Self.parse(json) else { continue }
                if snapshot.isPlaying {
                    target = candidate
                    return snapshot
                }
                // Keep following the tab already in use while it is merely paused.
                if paused == nil || candidate == target { paused = (candidate, snapshot) }
            }
        }
        target = paused?.0
        return paused?.1
    }

    private func musicTabs(in browser: Browser) -> [Target] {
        let script = """
        set sep to character id 9
        tell application "\(browser.name)"
            set out to ""
            repeat with w from 1 to (count of windows)
                try
                    repeat with t from 1 to (count of tabs of window w)
                        set out to out & w & sep & t & sep & (URL of tab t of window w) & linefeed
                    end repeat
                end try
            end repeat
            return out
        end tell
        """
        guard let listing = Self.osascript(script).output else { return [] }
        return listing.split(separator: "\n").compactMap { line in
            let parts = line.split(separator: "\t", maxSplits: 2).map(String.init)
            guard parts.count == 3, let window = Int(parts[0]), let tab = Int(parts[1]),
                  let host = URL(string: parts[2])?.host,
                  Self.hosts.contains(where: { host.contains($0) }) else { return nil }
            return Target(browser: browser.name, isSafari: browser.isSafari, window: window, tab: tab)
        }
    }

    private static func parse(_ json: String) -> PlayerSnapshot? {
        guard let object = try? JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any],
              let title = object["t"] as? String, !title.isEmpty else { return nil }
        let track = Track(
            source: .browser,
            // A page has no track identifier; the title and artist together stand in for one.
            id: title + "|" + (object["a"] as? String ?? ""),
            title: title,
            artist: object["a"] as? String ?? "",
            album: object["l"] as? String ?? "",
            duration: object["d"] as? Double ?? 0,
            artworkURL: (object["w"] as? String).flatMap(URL.init(string:))
        )
        return PlayerSnapshot(source: .browser, isPlaying: object["p"] as? Bool ?? false,
                              position: object["c"] as? Double ?? 0, volume: object["v"] as? Double ?? 100, track: track)
    }

    // MARK: Control

    func playPause() { act(Self.playPauseScript) }
    func pause() { act("(function(){\(Self.find)if(m)m.pause();})()") }
    func next() { act(Self.nextScript) }
    func previous() { act(Self.previousScript) }
    func seek(to seconds: Double) { act("(function(){\(Self.find)if(m)m.currentTime=\(seconds);})()") }
    func setVolume(to volume: Double) { act("(function(){\(Self.find)if(m)m.volume=\(volume / 100);})()") }

    private func act(_ script: String) {
        queue.async {
            guard let target = self.target else { return }
            _ = self.evaluate(script, in: [target])
        }
    }

    // MARK: AppleScript

    /// Runs the page script in each tab (all in one browser) and returns one result per tab, in order.
    private func evaluate(_ javascript: String, in targets: [Target]) -> [String] {
        guard let first = targets.first else { return [] }
        let escaped = javascript.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
        let calls = targets.map { target -> String in
            let command = target.isSafari
                ? "do JavaScript \"\(escaped)\" in tab \(target.tab) of window \(target.window)"
                : "execute tab \(target.tab) of window \(target.window) javascript \"\(escaped)\""
            return """
                try
                    set out to out & (\(command)) & linefeed
                on error message
                    set out to out & "ERROR " & message & linefeed
                end try
            """
        }
        let script = "tell application \"\(first.browser)\"\nset out to \"\"\n\(calls.joined(separator: "\n"))\nreturn out\nend tell"
        let lines = (Self.osascript(script).output ?? "").split(separator: "\n", omittingEmptySubsequences: false).map(String.init)

        // Both browser families mention JavaScript when the Apple Events setting is off.
        let refused = lines.contains { $0.hasPrefix("ERROR ") && $0.localizedCaseInsensitiveContains("JavaScript") }
        lock.lock()
        if refused { blockedNames.insert(first.browser) } else if !lines.isEmpty { blockedNames.remove(first.browser) }
        lock.unlock()
        return targets.indices.map { $0 < lines.count && !lines[$0].hasPrefix("ERROR ") ? lines[$0] : "" }
    }

    private static func osascript(_ source: String) -> (output: String?, error: String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-e", source]
        let out = Pipe(), err = Pipe()
        process.standardOutput = out
        process.standardError = err
        guard (try? process.run()) != nil else { return (nil, "") }
        let data = out.fileHandleForReading.readDataToEndOfFile()
        let problem = String(decoding: err.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        process.waitUntilExit()
        return (process.terminationStatus == 0 ? String(decoding: data, as: UTF8.self) : nil, problem)
    }
}
