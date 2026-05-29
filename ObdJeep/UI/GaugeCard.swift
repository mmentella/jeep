import SwiftUI

struct GaugeCard: View {
    let pid: ObdPid
    let reading: ObdReading?

    private var value: Double {
        reading?.value ?? pid.displayRange.lowerBound
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(pid.title)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Spacer()
                Text(pid.command)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
            }

            Gauge(value: value, in: pid.displayRange) {
                Text(pid.title)
            } currentValueLabel: {
                Text(formattedValue)
                    .font(.title3.monospacedDigit().weight(.bold))
            } minimumValueLabel: {
                Text(short(pid.displayRange.lowerBound))
            } maximumValueLabel: {
                Text(short(pid.displayRange.upperBound))
            }
            .gaugeStyle(.accessoryCircularCapacity)
            .tint(gradient)
            .frame(maxWidth: .infinity)

            HStack(alignment: .firstTextBaseline) {
                Text(formattedValue)
                    .font(.title2.monospacedDigit().weight(.bold))
                Text(pid.unit)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
            }
        }
        .padding(14)
        .frame(minHeight: 174)
        .background(Color.white.opacity(0.075), in: RoundedRectangle(cornerRadius: 8))
    }

    private var formattedValue: String {
        guard let reading else { return "--" }
        switch reading.pid {
        case .controlModuleVoltage:
            return String(format: "%.2f", reading.value)
        case .engineLoad, .throttlePosition:
            return String(format: "%.0f", reading.value)
        default:
            return String(format: "%.0f", reading.value)
        }
    }

    private var gradient: Gradient {
        Gradient(colors: [.mint, .cyan, .orange])
    }

    private func short(_ value: Double) -> String {
        String(format: "%.0f", value)
    }
}
