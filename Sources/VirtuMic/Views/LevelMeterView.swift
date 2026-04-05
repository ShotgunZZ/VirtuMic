import SwiftUI

struct LevelMeterView: View {
    let level: Float

    var body: some View {
        VStack(spacing: 2) {
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 3)
                        .fill(Color.black.opacity(0.3))

                    RoundedRectangle(cornerRadius: 3)
                        .fill(levelGradient)
                        .frame(width: barWidth(in: geometry.size.width))
                }
            }
            .frame(height: 8)

            Text(String(format: "%.1f dB", level))
                .font(.system(size: 9, design: .monospaced))
                .foregroundColor(.secondary)
        }
    }

    private func barWidth(in totalWidth: CGFloat) -> CGFloat {
        let normalized = (level + 60) / 60
        let clamped = max(0, min(1, normalized))
        return CGFloat(clamped) * totalWidth
    }

    private var levelGradient: LinearGradient {
        LinearGradient(
            colors: [.green, .green, .yellow, .red],
            startPoint: .leading,
            endPoint: .trailing
        )
    }
}
