import SwiftUI

/// A record with the cover art as its label; spins while music plays.
struct VinylView: View {
    let artwork: NSImage?
    let isPlaying: Bool
    /// The cover's hue, for the album-colored pressing.
    var hue: Double?

    @ObservedObject private var settings = Settings.shared
    @State private var spin = Spin()

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 60, paused: !isPlaying)) { context in
            record.rotationEffect(.degrees(spin.advance(to: context.date)))
        }
        .aspectRatio(1, contentMode: .fit)
    }

    private var record: some View {
        GeometryReader { geo in
            let size = min(geo.size.width, geo.size.height)
            let style = settings.vinylStyle
            ZStack {
                surface(style)
                ForEach(0..<9, id: \.self) { ring in
                    Circle()
                        .strokeBorder(Color.white.opacity(style == .classic ? 0.07 : 0.13), lineWidth: 0.6)
                        .padding(size * (0.03 + 0.027 * Double(ring)))
                }
                Circle()
                    .fill(AngularGradient(
                        colors: [.clear, .white.opacity(0.16), .clear, .clear, .white.opacity(0.16), .clear, .clear],
                        center: .center))
                if style != .picture {
                    label
                        .frame(width: size * 0.42, height: size * 0.42)
                        .clipShape(Circle())
                }
                Circle().fill(Color(white: 0.04)).frame(width: size * 0.035)
            }
            .frame(width: size, height: size)
            .clipShape(Circle())
            .shadow(color: .black.opacity(0.45), radius: size * 0.04, y: size * 0.02)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    @ViewBuilder private func surface(_ style: VinylStyle) -> some View {
        switch style {
        case .classic:
            Circle().fill(Color(white: 0.04))
        case .tinted:
            Circle().fill(hue.map { Color(hue: $0, saturation: 0.75, brightness: 0.42) } ?? Color(white: 0.18))
        case .picture:
            // The whole disc is the cover, the way a picture disc is pressed.
            label.overlay(Color.black.opacity(0.22))
        case .gold:
            Circle().fill(RadialGradient(colors: [Color(red: 0.95, green: 0.82, blue: 0.4), Color(red: 0.6, green: 0.44, blue: 0.1)],
                                         center: .center, startRadius: 0, endRadius: 200))
        }
    }

    @ViewBuilder private var label: some View {
        if let artwork {
            Image(nsImage: artwork).resizable().interpolation(.high).scaledToFill()
        } else {
            ZStack {
                Color(white: 0.22)
                Image(systemName: "music.note").font(.title2).foregroundStyle(.white.opacity(0.6))
            }
        }
    }
}

/// Accumulates rotation across pauses so the record resumes where it stopped.
private final class Spin {
    private var angle = 0.0
    private var last: Date?

    func advance(to date: Date) -> Double {
        if let last {
            let dt = date.timeIntervalSince(last)
            // A long gap means the timeline was paused, not that time passed spinning.
            if dt < 0.1 { angle = (angle + dt * 200).truncatingRemainder(dividingBy: 360) }  // 33⅓ rpm
        }
        last = date
        return angle
    }
}
