import SwiftUI

/// The main window: the record at full size with everything about the track beside it.
struct PlayerWindowView: View {
    @ObservedObject var model: MusicViewModel
    @ObservedObject var settings = Settings.shared

    var body: some View {
        HStack(spacing: 34) {
            VinylView(artwork: model.artwork, isPlaying: model.isPlaying, hue: model.artworkTint?.hue)
                .frame(width: 300, height: 300)
                .overlay(alignment: .topTrailing) {
                    Stylus(isPlaying: model.isPlaying).frame(width: 150, height: 186)
                }
                // The record is a picture of a physical thing and keeps its direction.
                .environment(\.layoutDirection, .leftToRight)

            VStack(alignment: .leading, spacing: 6) {
                Text(model.track?.title ?? L("Nothing playing"))
                    .font(.system(size: 30, weight: .bold))
                Text(model.track?.artist ?? model.idleMessage)
                    .font(.title2)
                    .foregroundStyle(.white.opacity(0.75))
                if let album = model.track?.album, !album.isEmpty {
                    Text(album).font(.title3).foregroundStyle(.white.opacity(0.5))
                }
                Spacer(minLength: 12)
                SpectrumView(isPlaying: model.isPlaying, barCount: 24, color: .white.opacity(0.85))
                    .frame(height: 36)
                Scrubber(model: model, large: true)
                HStack {
                    TransportControls(model: model, scale: 1.3)
                    Spacer()
                    VolumeSlider(model: model).frame(width: 150)
                    Button { settings.openWindow() } label: { Image(systemName: "gearshape.fill") }
                        .buttonStyle(.plain)
                        .foregroundStyle(.white.opacity(0.7))
                        .padding(.leading, 10)
                }
            }
            .lineLimit(1)
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(34)
        .frame(minWidth: 780, maxWidth: .infinity, minHeight: 380, maxHeight: .infinity)
        .background(
            LinearGradient(colors: [background, background.opacity(0.55)], startPoint: .topLeading, endPoint: .bottomTrailing)
                .background(.black)
                .ignoresSafeArea()  // run the color up under the transparent title bar
        )
        .ignoresSafeArea()
        .animation(.easeInOut(duration: 0.4), value: model.albumColor)
    }

    private var background: Color {
        settings.useAlbumColor ? model.albumColor : Color(white: 0.16)
    }
}
