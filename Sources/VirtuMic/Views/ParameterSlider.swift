import SwiftUI

struct ParameterSlider: View {
    let label: String
    @Binding var value: Float
    let range: ClosedRange<Float>
    let unit: String
    let format: String
    var logarithmic: Bool = false
    var onChange: ((Float) -> Void)?

    var body: some View {
        VStack(spacing: 2) {
            HStack {
                Text(label)
                    .font(.caption)
                    .foregroundColor(.secondary)
                Spacer()
                Text(String(format: format, value) + " " + unit)
                    .font(.caption.monospacedDigit())
                    .foregroundColor(.accentColor)
            }

            if logarithmic {
                Slider(value: Binding(
                    get: { log10f(max(value, range.lowerBound)) },
                    set: { newLog in
                        let newValue = powf(10, newLog)
                        value = newValue
                        onChange?(newValue)
                    }
                ), in: log10f(max(range.lowerBound, 0.0001))...log10f(range.upperBound))
                .controlSize(.small)
            } else {
                Slider(value: Binding(
                    get: { value },
                    set: { newValue in
                        value = newValue
                        onChange?(newValue)
                    }
                ), in: range)
                .controlSize(.small)
            }
        }
    }
}
