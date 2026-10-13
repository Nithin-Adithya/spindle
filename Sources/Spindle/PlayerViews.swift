import SwiftUI

struct TransportControls: View {
    @ObservedObject var model: MusicViewModel
    var scale: Double = 1
    var tint: Color = .white

    var body: some View {
        HStack(spacing: 22 * scale) {
            button("backward.fill", size: 16, action: model.previous)
            button(model.isPlaying ? "pause.fill" : "play.fill", size: 24, action: model.playPause)
            button("forward.fill", size: 16, action: model.next)
        }
        .foregroundStyle(tint)
        // Playback controls and seek bars keep their direction in right-to-left languages.
        .environment(\.layoutDirection, .leftToRight)
    }

    private func button(_ symbol: String, size: Double, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: size * scale))
                .frame(width: 34 * scale, height: 34 * scale)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

struct Scrubber: View {
    @ObservedObject var model: MusicViewModel
    var large = false
    var tint: Color = .white

    var body: some View {
        let duration = max(model.track?.duration ?? 0, 1)
        VStack(spacing: 2) {
            Slider(value: $model.position, in: 0...duration) { editing in
                model.isScrubbing = editing
                if !editing { model.seek(to: model.position) }
            }
            .controlSize(large ? .regular : .mini)
            .tint(tint)
            HStack {
                Text(Self.clock(model.position))
                Spacer()
                Text(Self.clock(model.track?.duration ?? 0))
            }
            .font((large ? Font.callout : Font.caption2).monospacedDigit())
            .foregroundStyle(tint.opacity(0.6))
        }
        .disabled(model.track == nil)
        .environment(\.layoutDirection, .leftToRight)
    }

    private static func clock(_ seconds: Double) -> String {
        let total = Int(seconds.rounded(.down))
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}

/// The menu-bar popover.
struct PlayerCardView: View {
    @ObservedObject var model: MusicViewModel
    @ObservedObject var settings = Settings.shared

    var body: some View {
        VStack(spacing: 12) {
            VinylView(artwork: model.artwork, isPlaying: model.isPlaying)
                .frame(width: 170, height: 170)

            VStack(spacing: 2) {
                Text(model.track?.title ?? L("Nothing playing"))
                    .font(.headline)
                Text(model.track?.artist ?? model.idleMessage)
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.7))
            }
            .lineLimit(1)
            .foregroundStyle(.white)

            SpectrumView(isPlaying: model.isPlaying, color: .white.opacity(0.85))
                .frame(width: 120, height: 22)

            Scrubber(model: model)
            TransportControls(model: model)

            Divider().overlay(.white.opacity(0.2))

            VStack(alignment: .leading, spacing: 6) {
                Toggle("Desktop widget", isOn: $settings.showWidget)
                Toggle("Notch display", isOn: $settings.showNotch)
                Toggle("Album color", isOn: $settings.useAlbumColor)
                HStack {
                    Button("Settings…") { settings.openWindow() }
                    Spacer()
                    Button("Quit Spindle") { NSApp.terminate(nil) }
                }
                .buttonStyle(.plain)
                .foregroundStyle(.white.opacity(0.7))
                .padding(.top, 2)
            }
            .toggleStyle(.switch)
            .controlSize(.mini)
            .font(.callout)
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(18)
        .frame(width: 260)
        .background(background)
        .animation(.easeInOut(duration: 0.4), value: model.albumColor)
    }

    private var background: Color {
        settings.useAlbumColor ? model.albumColor : Color(white: 0.16)
    }
}

/// Sits around the camera housing: cover on the left, bars on the right.
/// Hovering drops it open into a small player with controls; the window owner
/// watches the pointer, resizes the panel and flips `state.expanded`.
final class NotchState: ObservableObject {
    @Published var expanded = false
    /// Held open by the keyboard shortcut, regardless of where the pointer is.
    var pinned = false
}

struct NotchView: View {
    @ObservedObject var model: MusicViewModel
    @ObservedObject var state: NotchState
    @ObservedObject var settings = Settings.shared
    @Environment(\.colorScheme) private var systemScheme
    let notchWidth: Double
    let collapsedHeight: Double
    /// With a real camera housing the open player has to start below it.
    let hasNotch: Bool

    private var expanded: Bool { state.expanded }

    /// nil for the solid black pill, otherwise whether the glass is the dark kind.
    private var glassIsDark: Bool? {
        guard #available(macOS 26.0, *) else { return nil }
        switch settings.notchStyle {
        case .black: return nil
        case .glass: return systemScheme == .dark
        case .glassLight: return false
        case .glassDark: return true
        }
    }

    private var ink: Color { glassIsDark == false ? .black : .white }

    /// The cover's color, lifted or lowered just enough to read on the current surface.
    private var barColor: Color {
        guard let tint = model.artworkTint else { return ink.opacity(0.85) }
        // A soft wash of the cover's hue, not a saturated block of it.
        return Color(hue: tint.hue, saturation: min(tint.saturation, glassIsDark == false ? 0.6 : 0.42),
                     brightness: glassIsDark == false ? 0.5 : 1)
    }

    var body: some View {
        let open = Self.expandedSize(notchWidth: notchWidth, collapsedHeight: collapsedHeight, hasNotch: hasNotch)
        VStack(spacing: 10) {
            // The cover and the bars are the same views in both states, so they
            // grow and slide into place instead of being swapped out.
            HStack(spacing: expanded ? 14 : 0) {
                cover(size: expanded ? 92 : 20, radius: expanded ? 14 : 5)
                if expanded {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(model.track?.title ?? L("Nothing playing")).font(.title2.weight(.semibold))
                        Text(model.track?.artist ?? "—").font(.title3).foregroundStyle(ink.opacity(0.7))
                        if let album = model.track?.album, !album.isEmpty {
                            Text(album).font(.callout).foregroundStyle(ink.opacity(0.5))
                        }
                    }
                    .lineLimit(1)
                    .transition(.opacity)
                }
                Spacer(minLength: expanded ? 0 : notchWidth)
                SpectrumView(isPlaying: model.isPlaying, barCount: 6, color: barColor)
                    .frame(width: expanded ? 44 : 22, height: expanded ? 34 : 14)
            }
            .frame(height: expanded ? 92 : collapsedHeight)

            if expanded {
                Scrubber(model: model, large: true, tint: ink).transition(.opacity)
                TransportControls(model: model, scale: 1.2, tint: ink).transition(.opacity)
            }
        }
        .foregroundStyle(ink)
        .padding(.horizontal, expanded ? 22 : 10)
        .padding(.top, expanded ? (hasNotch ? collapsedHeight + 6 : 18) : 0)
        .frame(width: expanded ? open.width : notchWidth + Self.wing * 2,
               height: expanded ? open.height : collapsedHeight, alignment: .top)
        .background(surface)
        .clipped()
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .opacity(model.track == nil ? 0 : 1)
        .animation(.easeInOut(duration: 0.25), value: model.track == nil)
    }

    @ViewBuilder private var surface: some View {
        let radius = expanded ? 26.0 : 12.0
        let shape = UnevenRoundedRectangle(bottomLeadingRadius: radius, bottomTrailingRadius: radius, style: .continuous)
        if #available(macOS 26.0, *), let dark = glassIsDark {
            Color.clear
                // Glass takes its brightness from what is behind it, so over a dark
                // window even the light variant turns dark; the wash pins each look.
                .glassEffect(.regular, in: shape)
                .overlay(shape.fill(dark ? Color.black.opacity(0.25) : Color.white.opacity(0.6)))
                .environment(\.colorScheme, dark ? .dark : .light)
        } else {
            shape.fill(.black)
        }
    }

    private func cover(size: Double, radius: Double) -> some View {
        Group {
            if let artwork = model.artwork {
                Image(nsImage: artwork).resizable().interpolation(.high).scaledToFill()
            } else {
                Color(white: 0.25)
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
    }

    static let wing = 40.0

    static func expandedSize(notchWidth: Double, collapsedHeight: Double, hasNotch: Bool) -> CGSize {
        CGSize(width: max(notchWidth + wing * 2, 520), height: (hasNotch ? collapsedHeight + 6 : 18) + 222)
    }
}
