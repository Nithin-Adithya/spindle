import SwiftUI

/// The desktop widget. Each theme is laid out at its base size and then scaled
/// as a whole, so every size setting keeps the same proportions.
struct WidgetView: View {
    @ObservedObject var model: MusicViewModel
    @ObservedObject var settings = Settings.shared

    static func size(for settings: Settings) -> CGSize {
        let base = settings.widgetTheme.baseSize, scale = settings.widgetSize.scale
        return CGSize(width: base.width * scale, height: base.height * scale)
    }

    var body: some View {
        let base = settings.widgetTheme.baseSize, scale = settings.widgetSize.scale
        Group {
            switch settings.widgetTheme {
            case .sleeve: sleeveTheme
            case .turntable: turntableTheme
            case .compact: compactTheme
            case .cover: coverTheme
            case .record: recordTheme
            }
        }
        .lineLimit(1)
        .fontDesign(settings.widgetFont.design)
        .foregroundStyle(.white)
        .frame(width: base.width, height: base.height)
        .background { if settings.widgetTheme != .record { background } }
        .clipShape(RoundedRectangle(cornerRadius: settings.widgetTheme == .record ? 0 : 26, style: .continuous))
        .scaleEffect(scale)
        .frame(width: base.width * scale, height: base.height * scale)
        .animation(.easeInOut(duration: 0.4), value: model.albumColor)
    }

    // MARK: Themes

    private var sleeveTheme: some View {
        HStack(spacing: 0) {
            ZStack(alignment: .leading) {
                record(150).offset(x: model.isPlaying ? 70 : 20)
                cover(150, radius: 10).shadow(color: .black.opacity(0.4), radius: 8, x: 4)
            }
            .frame(width: 230, alignment: .leading)
            .animation(.spring(duration: 0.6), value: model.isPlaying)

            VStack(alignment: .leading, spacing: 8) {
                titles(19, alignment: .leading)
                Spacer(minLength: 0)
                if settings.widgetProgress { Scrubber(model: model) }
                TransportControls(model: model, scale: 0.85).frame(maxWidth: .infinity)
            }
            .frame(width: 190, alignment: .leading)
        }
        .padding(18)
    }

    private var turntableTheme: some View {
        VStack(spacing: 10) {
            record(206)
                .padding(6)
                .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(.black.opacity(0.22)))
            titles(15, alignment: .center)
            if settings.widgetProgress { Scrubber(model: model) }
            TransportControls(model: model, scale: 0.9)
        }
        .padding(16)
    }

    private var compactTheme: some View {
        HStack(spacing: 12) {
            cover(72, radius: 12)
            VStack(alignment: .leading, spacing: 4) {
                titles(15, alignment: .leading)
                if settings.widgetProgress { Scrubber(model: model) }
            }
            TransportControls(model: model, scale: 0.7)
        }
        .padding(16)
    }

    private var coverTheme: some View {
        ZStack(alignment: .bottom) {
            cover(250, radius: 0)
            VStack(spacing: 6) {
                titles(16, alignment: .center)
                if settings.widgetProgress { Scrubber(model: model) }
                TransportControls(model: model, scale: 0.8)
            }
            .padding(.horizontal, 16)
            .padding(.top, 34)
            .padding(.bottom, 10)
            .background(LinearGradient(colors: [.clear, .black.opacity(0.8)], startPoint: .top,
                                       endPoint: UnitPoint(x: 0.5, y: 0.45)))
        }
    }

    private var recordTheme: some View {
        record(214)
            .contentShape(Circle())
            .onTapGesture { model.playPause() }
    }

    // MARK: Pieces

    private func titles(_ size: Double, alignment: HorizontalAlignment) -> some View {
        VStack(alignment: alignment, spacing: 3) {
            Text(model.track?.title ?? L("Nothing playing"))
                .font(.system(size: size * settings.widgetTitleSize.scale, weight: .semibold))
                .foregroundStyle(Color(hex: settings.widgetTitleColor))
            Text(model.track?.artist ?? model.idleMessage)
                .font(.system(size: 12.5 * settings.widgetSubtitleSize.scale))
                .foregroundStyle(.white.opacity(0.7))
        }
        .frame(maxWidth: .infinity, alignment: Alignment(horizontal: alignment, vertical: .center))
    }

    private func record(_ size: Double) -> some View {
        VinylView(artwork: model.artwork, isPlaying: model.isPlaying, hue: model.artworkTint?.hue)
            .frame(width: size, height: size)
            .overlay(alignment: .topTrailing) {
                if settings.widgetStylus { Stylus(isPlaying: model.isPlaying).frame(width: size * 0.5, height: size * 0.62) }
            }
    }

    private func cover(_ size: Double, radius: Double) -> some View {
        Group {
            if let artwork = model.artwork {
                Image(nsImage: artwork).resizable().interpolation(.high).scaledToFill()
            } else {
                ZStack {
                    Color(white: 0.25)
                    Image(systemName: "music.note").font(.system(size: size * 0.3)).foregroundStyle(.white.opacity(0.5))
                }
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
    }

    @ViewBuilder private var background: some View {
        switch settings.widgetBackground {
        case .album:
            settings.useAlbumColor ? model.albumColor : Color(white: 0.16)
        case .cover:
            if let artwork = model.artwork {
                Image(nsImage: artwork).resizable().scaledToFill().blur(radius: 28).overlay(.black.opacity(0.4))
            } else {
                Color(white: 0.16)
            }
        case .color:
            Color(hex: settings.widgetColor)
        case .image:
            if let image = Self.image(at: settings.widgetImagePath) {
                Image(nsImage: image).resizable().scaledToFill().overlay(.black.opacity(0.3))
            } else {
                Color(white: 0.16)
            }
        case .glass:
            if #available(macOS 26.0, *) {
                Color.clear.glassEffect(.regular, in: RoundedRectangle(cornerRadius: 26, style: .continuous))
            } else {
                model.albumColor
            }
        case .transparent:
            Color.clear
        }
    }

    /// The view redraws every second; reading the file each time would be wasteful.
    private static var cached: (path: String, image: NSImage?) = ("", nil)

    private static func image(at path: String) -> NSImage? {
        if cached.path != path { cached = (path, NSImage(contentsOfFile: path)) }
        return cached.image
    }
}

/// A tonearm pivoting from the top-right corner; it swings onto the record while music plays.
struct Stylus: View {
    let isPlaying: Bool

    var body: some View {
        GeometryReader { geo in
            let pivot = CGPoint(x: geo.size.width * 0.82, y: geo.size.width * 0.18)
            let length = geo.size.height * 0.82
            ZStack {
                Path { path in
                    path.move(to: pivot)
                    path.addLine(to: CGPoint(x: pivot.x, y: pivot.y + length))
                }
                .stroke(Color(white: 0.82), style: StrokeStyle(lineWidth: geo.size.width * 0.045, lineCap: .round))
                RoundedRectangle(cornerRadius: 2)
                    .fill(Color(white: 0.65))
                    .frame(width: geo.size.width * 0.13, height: geo.size.width * 0.2)
                    .position(x: pivot.x, y: pivot.y + length)
            }
            .rotationEffect(.degrees(isPlaying ? 24 : 2), anchor: UnitPoint(x: 0.82, y: pivot.y / geo.size.height))
            .animation(.spring(duration: 0.7), value: isPlaying)
            Circle()
                .fill(Color(white: 0.5))
                .overlay(Circle().fill(Color(white: 0.85)).padding(geo.size.width * 0.04))
                .frame(width: geo.size.width * 0.2, height: geo.size.width * 0.2)
                .position(pivot)
        }
        .shadow(color: .black.opacity(0.35), radius: 3, y: 2)
        .allowsHitTesting(false)
    }
}
