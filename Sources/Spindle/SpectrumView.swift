import SwiftUI

/// Decorative bars: the levels are random, not measured from the audio, so no
/// microphone or audio-capture permission is needed.
struct SpectrumView: View {
    let isPlaying: Bool
    var barCount = 14
    var color: Color = .white

    @State private var levels: [Double] = []

    private let tick = Timer.publish(every: 0.3, on: .main, in: .common).autoconnect()
    private static let floor = -35.0  // dB

    var body: some View {
        GeometryReader { geo in
            HStack(alignment: .center, spacing: geo.size.width / Double(barCount) * 0.4) {
                ForEach(0..<barCount, id: \.self) { index in
                    Capsule()
                        .fill(color)
                        .frame(height: max(2, geo.size.height * height(at: index)))
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .onReceive(tick) { _ in
            withAnimation(.easeInOut(duration: 0.3)) {
                levels = (0..<barCount).map { _ in isPlaying ? Double.random(in: Self.floor...0) : Self.floor }
            }
        }
    }

    private func height(at index: Int) -> Double {
        guard index < levels.count else { return 0 }
        return 1 - levels[index] / Self.floor
    }
}
