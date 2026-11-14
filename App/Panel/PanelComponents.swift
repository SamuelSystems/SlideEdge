import SwiftUI

extension Color {
    /// SlideEdge violet, taken from the app icon.
    static let edgeAccent = Color(red: 0.36, green: 0.29, blue: 0.93)
    static let brightnessTint = Color(red: 0.95, green: 0.55, blue: 0.15)
    static let volumeTint = Color(red: 0.20, green: 0.47, blue: 0.96)
}

/// Logo and title shown at the top of each panel page.
struct PanelHeader<Trailing: View>: View {
    let title: String
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack(spacing: 10) {
            Image("LogoMark")
                .resizable()
                .frame(width: 26, height: 26)
            Text(title)
                .font(.system(size: 17, weight: .semibold))
            Spacer()
            trailing
        }
    }
}

/// Icon disc, title, optional subtitle and a trailing control.
struct PanelRow<Trailing: View>: View {
    let symbol: String
    var highlighted = false
    let title: String
    var subtitle: String?
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack(spacing: 12) {
            IconDisc(symbol: symbol, highlighted: highlighted)
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.system(size: 13, weight: .semibold))
                if let subtitle {
                    Text(subtitle)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 8)
            trailing
        }
    }
}

/// A row with a switch; the icon lights up while the option is on.
struct ToggleRow: View {
    let symbol: String
    let title: String
    var subtitle: String?
    @Binding var isOn: Bool

    var body: some View {
        PanelRow(symbol: symbol, highlighted: isOn, title: title, subtitle: subtitle) {
            Toggle(title, isOn: $isOn)
                .labelsHidden()
                .toggleStyle(AccentSwitchStyle())
        }
    }
}

/// Switch drawn in the SlideEdge accent: the system switch ignores `.tint` on recent macOS.
struct AccentSwitchStyle: ToggleStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        Button {
            configuration.isOn.toggle()
        } label: {
            Capsule()
                .fill(configuration.isOn ? Color.edgeAccent : Color.primary.opacity(0.14))
                .frame(width: 34, height: 20)
                .overlay(alignment: configuration.isOn ? .trailing : .leading) {
                    Circle()
                        .fill(.white)
                        .shadow(color: .black.opacity(0.2), radius: 1, y: 0.5)
                        .padding(2)
                }
                .animation(.easeOut(duration: 0.15), value: configuration.isOn)
                .opacity(isEnabled ? 1 : 0.5)
        }
        .buttonStyle(.plain)
        .accessibilityRepresentation {
            Toggle(isOn: configuration.$isOn) { configuration.label }
        }
    }
}

struct IconDisc: View {
    let symbol: String
    var highlighted = false

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(highlighted ? Color.white : Color.primary.opacity(0.75))
            .frame(width: 30, height: 30)
            .background(Circle().fill(highlighted ? Color.edgeAccent : Color.primary.opacity(0.07)))
            .animation(.easeOut(duration: 0.15), value: highlighted)
    }
}

struct SectionTitle: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Slider with a filled track, step dots and a round knob.
struct StepSlider: View {
    @Binding var value: Double
    let range: ClosedRange<Double>
    let step: Double
    var accessibilityLabel: String

    private let knob: CGFloat = 20

    var body: some View {
        GeometryReader { geometry in
            let span = range.upperBound - range.lowerBound
            let steps = Int((span / step).rounded())
            let usable = max(geometry.size.width - knob, 1)
            let fraction = min(max((value - range.lowerBound) / span, 0), 1)
            let knobX = knob / 2 + usable * fraction
            let midY = geometry.size.height / 2

            ZStack(alignment: .leading) {
                Capsule().fill(Color.primary.opacity(0.08))
                ForEach(0...steps, id: \.self) { index in
                    Circle()
                        .fill(Color.primary.opacity(0.22))
                        .frame(width: 3, height: 3)
                        .position(x: knob / 2 + usable * Double(index) / Double(steps), y: midY)
                }
                Capsule()
                    .fill(Color.edgeAccent)
                    .frame(width: knobX + knob / 2)
                Circle()
                    .fill(.white)
                    .shadow(color: .black.opacity(0.25), radius: 1.5, y: 0.5)
                    .frame(width: knob - 6, height: knob - 6)
                    .position(x: knobX, y: midY)
            }
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0).onChanged { drag in
                let fraction = min(max((drag.location.x - knob / 2) / usable, 0), 1)
                set(range.lowerBound + fraction * span)
            })
        }
        .frame(height: knob + 2)
        .accessibilityElement()
        .accessibilityLabel(accessibilityLabel)
        .accessibilityValue(String(format: "%.2f", value))
        .accessibilityAdjustableAction { direction in
            set(value + (direction == .increment ? step : -step))
        }
    }

    private func set(_ raw: Double) {
        let snapped = ((raw - range.lowerBound) / step).rounded() * step + range.lowerBound
        let clamped = min(max(snapped, range.lowerBound), range.upperBound)
        if abs(clamped - value) > step / 1000 { value = clamped }
    }
}

/// Title + value line above a `StepSlider`.
struct SliderRow: View {
    let symbol: String
    let title: String
    let valueText: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    let step: Double

    var body: some View {
        VStack(spacing: 8) {
            PanelRow(symbol: symbol, title: title) {
                Text(valueText)
                    .font(.system(size: 13, weight: .medium).monospacedDigit())
            }
            StepSlider(value: $value, range: range, step: step, accessibilityLabel: title)
                .padding(.leading, 42)
        }
    }
}

/// Plain icon button for the panel footer.
struct FooterIconButton: View {
    let symbol: String
    let help: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 15))
                .frame(width: 26, height: 26)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(.secondary)
        .help(help)
        .accessibilityLabel(help)
    }
}
