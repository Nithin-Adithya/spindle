import AppKit
import Combine
import SwiftUI

final class MusicViewModel: ObservableObject {
    @Published private(set) var track: Track?
    @Published private(set) var isPlaying = false
    @Published private(set) var artwork: NSImage?
    @Published private(set) var albumColor = Color(white: 0.16)
    /// The cover's own color (hue and saturation), for accents drawn on top of other surfaces.
    @Published private(set) var artworkTint: (hue: Double, saturation: Double)?
    @Published var position: Double = 0
    /// The player's own volume, 0 to 100.
    @Published var volume: Double = 100
    var isAdjustingVolume = false
    /// Shown in place of the artist when there is no track.
    @Published private(set) var idleMessage = L("Open Spotify or Music to play")
    /// When set, playback is paused once this moment passes.
    @Published var sleepDeadline: Date?
    /// Browsers that refused the page script and need a setting turned on.
    @Published private(set) var blockedBrowsers: [String] = []

    /// Set while the user drags the scrubber so polling doesn't fight the drag.
    var isScrubbing = false

    private let bridge = PlayerBridge()
    private var lastActive: PlayerSource?
    private var timer: Timer?
    private var artworkTrackID: String?

    init() {
        let center = DistributedNotificationCenter.default()
        for source in PlayerSource.allCases {
            for name in source.notificationNames {
                center.addObserver(forName: Notification.Name(name), object: nil, queue: .main) { [weak self] _ in
                    self?.lastActive = source
                    self?.refresh()
                }
            }
        }
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            self?.checkSleepTimer()
            self?.refresh()
        }
        refresh()
    }

    // MARK: Controls

    func playPause() { send { $0.playPause($1) } }
    func next() { send { $0.next($1) } }
    func previous() { send { $0.previous($1) } }

    func seek(to seconds: Double) {
        position = seconds
        send { $0.seek($1, to: seconds) }
    }

    func setVolume(_ value: Double) {
        volume = value
        send { $0.setVolume($1, to: value) }
    }

    private func checkSleepTimer() {
        guard let deadline = sleepDeadline, deadline <= Date() else { return }
        sleepDeadline = nil
        if isPlaying { send { $0.pause($1) } }
    }

    private func send(_ action: @escaping (PlayerBridge, PlayerSource) -> Void) {
        let allowed = Settings.shared.source.sources
        guard let source = track?.source ?? lastActive.flatMap({ allowed.contains($0) ? $0 : nil })
            ?? allowed.first(where: \.isRunning) else { return }
        PlayerBridge.queue.async { [bridge] in action(bridge, source) }
        refresh()
    }

    // MARK: Polling

    private func refresh() {
        let preferred = lastActive
        let allowed = Settings.shared.source.sources
        PlayerBridge.queue.async { [weak self, bridge] in
            let snapshots = allowed.compactMap { bridge.snapshot(of: $0) }
            let playing = snapshots.filter(\.isPlaying)
            let chosen = playing.first { $0.source == preferred }
                ?? playing.first
                ?? snapshots.first { $0.source == preferred && $0.track != nil }
                ?? snapshots.first { $0.track != nil }
            let anyRunning = !snapshots.isEmpty
            let blocked = bridge.blockedBrowsers.sorted()
            DispatchQueue.main.async {
                if self?.blockedBrowsers != blocked { self?.blockedBrowsers = blocked }
                self?.apply(chosen, anyRunning: anyRunning)
            }
        }
    }

    private func apply(_ snapshot: PlayerSnapshot?, anyRunning: Bool) {
        let message = anyRunning ? L("Music is stopped") : L("Open Spotify or Music to play")
        if idleMessage != message { idleMessage = message }
        if let snapshot, snapshot.isPlaying { lastActive = snapshot.source }
        if track != snapshot?.track { track = snapshot?.track }
        let playing = snapshot?.isPlaying ?? false
        if isPlaying != playing { isPlaying = playing }
        if !isScrubbing { position = snapshot?.position ?? 0 }
        if !isAdjustingVolume, let level = snapshot?.volume, level != volume { volume = level }
        loadArtworkIfNeeded()
    }

    private func loadArtworkIfNeeded() {
        let key = track.map { "\($0.source.rawValue):\($0.id)" }
        guard key != artworkTrackID else { return }
        artworkTrackID = key
        guard let track else { return setArtwork(nil, for: key) }

        switch track.source {
        case .music:
            PlayerBridge.queue.async { [weak self, bridge] in
                let image = bridge.musicArtwork()
                DispatchQueue.main.async { self?.setArtwork(image, for: key) }
            }
        case .spotify, .browser:
            guard let url = track.artworkURL else { return setArtwork(nil, for: key) }
            URLSession.shared.dataTask(with: url) { [weak self] data, _, _ in
                let image = data.flatMap(NSImage.init(data:))
                DispatchQueue.main.async { self?.setArtwork(image, for: key) }
            }.resume()
        }
    }

    private func setArtwork(_ image: NSImage?, for key: String?) {
        guard key == artworkTrackID else { return }  // a newer track has replaced this one
        artwork = image
        let ambient = image.flatMap(Self.ambientColor).map {
            NSColor(srgbRed: $0.r, green: $0.g, blue: $0.b, alpha: 1)
        }
        artworkTint = ambient.map { (Double($0.hueComponent), Double($0.saturationComponent)) }
        // Backgrounds keep the hue but stay dark and muted so white text reads on any cover.
        albumColor = ambient.map {
            Color(hue: Double($0.hueComponent), saturation: min(Double($0.saturationComponent), 0.5),
                  brightness: min(Double($0.brightnessComponent), 0.3))
        } ?? Color(white: 0.16)
    }

    /// The color the cover gives off around its edges: the strongest hue in the
    /// outer band of the image, the way an ambient glow behind it would look.
    private static func ambientColor(of image: NSImage) -> (r: Double, g: Double, b: Double)? {
        let side = 40, band = 6
        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil),
              let context = CGContext(data: nil, width: side, height: side, bitsPerComponent: 8, bytesPerRow: side * 4,
                                      space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return nil }
        context.interpolationQuality = .medium
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: side, height: side))
        guard let data = context.data else { return nil }
        let pixels = data.bindMemory(to: UInt8.self, capacity: side * side * 4)

        // Group edge pixels by hue, weighting vivid ones, and keep the heaviest group.
        var buckets = [(weight: Double, r: Double, g: Double, b: Double)](repeating: (0, 0, 0, 0), count: 12)
        var plain = (r: 0.0, g: 0.0, b: 0.0, n: 0.0)
        for y in 0..<side {
            for x in 0..<side where x < band || x >= side - band || y < band || y >= side - band {
                let i = (y * side + x) * 4
                let r = Double(pixels[i]) / 255, g = Double(pixels[i + 1]) / 255, b = Double(pixels[i + 2]) / 255
                plain = (plain.r + r, plain.g + g, plain.b + b, plain.n + 1)
                let color = NSColor(srgbRed: r, green: g, blue: b, alpha: 1)
                let weight = Double(color.saturationComponent * color.brightnessComponent)
                let bucket = min(11, Int(color.hueComponent * 12))
                buckets[bucket] = (buckets[bucket].weight + weight, buckets[bucket].r + r * weight,
                                   buckets[bucket].g + g * weight, buckets[bucket].b + b * weight)
            }
        }
        guard let best = buckets.max(by: { $0.weight < $1.weight }), best.weight > plain.n * 0.02 else {
            // A greyscale edge has no hue to pick; fall back to its plain average.
            return plain.n > 0 ? (plain.r / plain.n, plain.g / plain.n, plain.b / plain.n) : nil
        }
        return (best.r / best.weight, best.g / best.weight, best.b / best.weight)
    }
}
