import SwiftUI

struct LevelInfo {
    let title: String
    let symbol: String
    let tint: Color
    /// nil when the control is unavailable.
    let value: Double?
    var muted = false
}

/// The two side-edge levels, laid out like the edges they belong to.
struct LevelsCard: View {
    let left: LevelInfo
    let right: LevelInfo

    var body: some View {
        HStack(spacing: 14) {
            LevelBar(value: left.muted ? 0 : left.value, tint: left.tint)
            LevelReadout(info: left, alignment: .leading)
            Spacer(minLength: 0)
            LevelReadout(info: right, alignment: .trailing)
            LevelBar(value: right.muted ? 0 : right.value, tint: right.tint)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 16)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.primary.opacity(0.045))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.07))
        )
    }
}

private struct LevelReadout: View {
    let info: LevelInfo
    let alignment: HorizontalAlignment

    var body: some View {
        VStack(alignment: alignment, spacing: 6) {
            HStack(spacing: 6) {
                if alignment == .leading { icon }
                Text(info.title.uppercased())
                    .font(.system(size: 11, weight: .semibold))
                    .kerning(1.2)
                    .foregroundStyle(.secondary)
                if alignment == .trailing { icon }
            }
            value
        }
        .accessibilityElement(children: .combine)
    }

    private var icon: some View {
        Image(systemName: info.muted ? "speaker.slash.fill" : info.symbol)
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(info.tint)
    }

    @ViewBuilder private var value: some View {
        if let level = info.value {
            HStack(alignment: .firstTextBaseline, spacing: 1) {
                Text(info.muted ? "Muto" : "\(Int((level * 100).rounded()))")
                    .font(.system(size: info.muted ? 28 : 40, weight: .regular).monospacedDigit())
                if !info.muted {
                    Text("%").font(.system(size: 16, weight: .regular))
                }
            }
        } else {
            Text("—")
                .font(.system(size: 40, weight: .regular))
                .foregroundStyle(.tertiary)
        }
    }
}

private struct LevelBar: View {
    let value: Double?
    let tint: Color

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .bottom) {
                Capsule().fill(Color.primary.opacity(0.08))
                Capsule()
                    .fill(tint)
                    .frame(height: geometry.size.height * (value ?? 0))
            }
        }
        .frame(width: 4, height: 72)
        .animation(.easeOut(duration: 0.15), value: value)
    }
}
