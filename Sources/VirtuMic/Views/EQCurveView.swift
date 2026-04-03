import SwiftUI
import AVFoundation

struct EQCurveView: View {
    let bands: [EQBandConfig]
    let sampleRate: Double
    let selectedBand: Int?

    private let bandColors: [Color] = [
        .purple, .pink, .green, .yellow, .cyan, .orange, .blue, .red,
    ]

    var body: some View {
        GeometryReader { geometry in
            let w = geometry.size.width
            let h = geometry.size.height

            ZStack {
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color.black.opacity(0.4))

                gridLines(width: w, height: h)

                curveFilledPath(width: w, height: h)
                    .fill(
                        LinearGradient(
                            colors: [Color.green.opacity(0.25), Color.green.opacity(0.02)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )

                curvePath(width: w, height: h)
                    .stroke(Color.green, lineWidth: 2)

                ForEach(0..<bands.count, id: \.self) { i in
                    let x = freqToX(bands[i].frequency, width: w)
                    let gain = totalResponseAtBandFreq(bandIndex: i)
                    let y = dbToY(gain, height: h)
                    Circle()
                        .fill(bandColors[i % bandColors.count])
                        .frame(width: selectedBand == i ? 12 : 8, height: selectedBand == i ? 12 : 8)
                        .overlay(
                            Circle().stroke(Color.white, lineWidth: selectedBand == i ? 2 : 1)
                        )
                        .position(x: x, y: y)
                }

                axisLabels(width: w, height: h)
            }
        }
        .frame(height: 100)
    }

    private func curvePath(width: CGFloat, height: CGFloat) -> Path {
        Path { path in
            let steps = Int(width)
            for step in 0...steps {
                let x = CGFloat(step)
                let freq = xToFreq(x, width: width)
                let totalDB = totalResponse(at: freq)
                let y = dbToY(totalDB, height: height)
                if step == 0 { path.move(to: CGPoint(x: x, y: y)) }
                else { path.addLine(to: CGPoint(x: x, y: y)) }
            }
        }
    }

    private func curveFilledPath(width: CGFloat, height: CGFloat) -> Path {
        var path = curvePath(width: width, height: height)
        path.addLine(to: CGPoint(x: width, y: height))
        path.addLine(to: CGPoint(x: 0, y: height))
        path.closeSubpath()
        return path
    }

    private func totalResponse(at freq: Float) -> Float {
        bands.reduce(Float(0)) { $0 + bandResponse(band: $1, at: freq) }
    }

    private func totalResponseAtBandFreq(bandIndex: Int) -> Float {
        let freq = bands[bandIndex].frequency
        return totalResponse(at: freq)
    }

    private func bandResponse(band: EQBandConfig, at freq: Float) -> Float {
        let filterType = AudioConfig.filterType(from: band.filterType)
        let f0 = band.frequency
        let gain = band.gain
        let bw = band.bandwidth
        let ratio = freq / f0

        switch filterType {
        case .highPass:
            let n = ratio * ratio
            return 20 * log10f(max(n / (1.0 + n), 0.0001))
        case .lowPass:
            let invRatio = 1.0 / (ratio * ratio)
            return 20 * log10f(max(invRatio / (1.0 + invRatio), 0.0001))
        case .parametric:
            let logRatio = log2f(max(ratio, 0.001))
            let shape = expf(-2.0 * logRatio * logRatio / (bw * bw))
            return gain * shape
        case .highShelf:
            let transition = log2f(max(ratio, 0.01))
            let shape = 1.0 / (1.0 + expf(-4.0 * transition))
            return gain * shape
        case .lowShelf:
            let transition = log2f(max(ratio, 0.01))
            let shape = 1.0 / (1.0 + expf(4.0 * transition))
            return gain * shape
        case .bandPass:
            let logRatio = log2f(max(ratio, 0.001))
            let shape = expf(-2.0 * logRatio * logRatio / (bw * bw))
            return 20 * log10f(max(shape, 0.0001))
        case .bandStop:
            let logRatio = log2f(max(ratio, 0.001))
            let shape = 1.0 - expf(-2.0 * logRatio * logRatio / (bw * bw))
            return 20 * log10f(max(shape, 0.0001))
        default:
            return 0
        }
    }

    private func freqToX(_ freq: Float, width: CGFloat) -> CGFloat {
        let minLog = log10f(20)
        let maxLog = log10f(20000)
        let normalized = (log10f(max(freq, 20)) - minLog) / (maxLog - minLog)
        return CGFloat(normalized) * width
    }

    private func xToFreq(_ x: CGFloat, width: CGFloat) -> Float {
        let minLog = log10f(20)
        let maxLog = log10f(20000)
        let normalized = Float(x / width)
        return powf(10, minLog + normalized * (maxLog - minLog))
    }

    private func dbToY(_ db: Float, height: CGFloat) -> CGFloat {
        let clamped = max(-12, min(12, db))
        let normalized = (12 - clamped) / 24
        return CGFloat(normalized) * height
    }

    private func gridLines(width: CGFloat, height: CGFloat) -> some View {
        ZStack {
            Path { path in
                let y = height / 2
                path.move(to: CGPoint(x: 0, y: y))
                path.addLine(to: CGPoint(x: width, y: y))
            }
            .stroke(Color.gray.opacity(0.3), lineWidth: 1)

            ForEach([-6, 6], id: \.self) { db in
                Path { path in
                    let y = dbToY(Float(db), height: height)
                    path.move(to: CGPoint(x: 0, y: y))
                    path.addLine(to: CGPoint(x: width, y: y))
                }
                .stroke(Color.gray.opacity(0.15), lineWidth: 0.5)
            }
        }
    }

    private func axisLabels(width: CGFloat, height: CGFloat) -> some View {
        ZStack {
            ForEach([100, 1000, 10000], id: \.self) { freq in
                Text(freq >= 1000 ? "\(freq/1000)k" : "\(freq)")
                    .font(.system(size: 7))
                    .foregroundColor(.gray.opacity(0.5))
                    .position(x: freqToX(Float(freq), width: width), y: height - 6)
            }
            Text("+12").font(.system(size: 7)).foregroundColor(.gray.opacity(0.5)).position(x: 14, y: 6)
            Text("0").font(.system(size: 7)).foregroundColor(.gray.opacity(0.5)).position(x: 8, y: height / 2)
            Text("-12").font(.system(size: 7)).foregroundColor(.gray.opacity(0.5)).position(x: 14, y: height - 14)
        }
    }
}
