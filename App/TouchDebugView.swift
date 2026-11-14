import SwiftUI
import AppSettings
import GestureEngine
import TouchInput

struct TouchDebugView: View {
    @EnvironmentObject private var monitor: TouchMonitor
    @EnvironmentObject private var gestureLog: GestureLog
    @EnvironmentObject private var settings: AppSettings

    var body: some View {
        ScrollView {
            content.padding(20)
        }
        .frame(width: 560, height: 560)
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 16) {
            switch monitor.status {
            case .unavailable(let reason):
                Label(reason, systemImage: "exclamationmark.triangle.fill").foregroundStyle(.orange)
            case .stopped:
                Label("Lettura tocchi ferma (SlideEdge disattivato)", systemImage: "pause.circle")
                    .foregroundStyle(.secondary)
            case .running where monitor.devices.isEmpty:
                Label("Nessun dispositivo multitouch", systemImage: "questionmark.circle")
                    .foregroundStyle(.secondary)
            case .running:
                EmptyView()
            }

            GestureSection(log: gestureLog, swapSides: settings.swapSides)

            ForEach(monitor.devices) { device in
                DeviceSurfaceView(
                    device: device,
                    frame: monitor.latestFrames[device.id],
                    rate: monitor.frameRates[device.id],
                    edgeWidth: settings.edgeWidth
                )
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }
}

private struct GestureSection: View {
    @ObservedObject var log: GestureLog
    let swapSides: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Gesti").font(.headline)
            HStack(spacing: 16) {
                LevelBar(title: swapSides ? "Sinistra · volume" : "Sinistra · luminosità", value: log.levels[.left] ?? 0)
                LevelBar(title: swapSides ? "Destra · luminosità" : "Destra · volume", value: log.levels[.right] ?? 0)
                LevelBar(title: "Alto · tastiera", value: log.levels[.top] ?? 0)
            }
            VStack(alignment: .leading, spacing: 2) {
                if log.entries.isEmpty {
                    Text("Nessun gesto riconosciuto").foregroundStyle(.secondary)
                }
                ForEach(log.entries) { entry in
                    HStack(spacing: 8) {
                        Text(entry.date, format: .dateTime.hour().minute().second())
                            .foregroundStyle(.secondary)
                        Text(entry.text)
                    }
                }
            }
            .font(.caption.monospaced())
            .frame(maxWidth: .infinity, minHeight: 80, alignment: .topLeading)
        }
    }
}

private struct LevelBar: View {
    let title: String
    let value: Double

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            ProgressView(value: value)
            Text("\(Int((value * 16).rounded()))/16").font(.caption2.monospacedDigit()).foregroundStyle(.secondary)
        }
    }
}

private struct DeviceSurfaceView: View {
    let device: TouchDeviceInfo
    let frame: TouchFrame?
    let rate: Int?
    let edgeWidth: Double

    private var aspect: Double {
        device.width > 0 && device.height > 0 ? device.width / device.height : 1.5
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(device.kind.title).font(.headline)
                Text(device.width > 0 ? "\(Int(device.width))×\(Int(device.height)) mm · family \(device.familyID)" : "family \(device.familyID)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                if !device.isRunning {
                    Text("non avviato").font(.caption).foregroundStyle(.red)
                } else if let rate {
                    Text("\(rate) Hz").font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                }
            }

            Canvas { context, size in
                draw(in: &context, size: size)
            }
            .aspectRatio(aspect, contentMode: .fit)
            .frame(maxWidth: device.kind == .magicMouse ? 200 : .infinity)

            let touches = frame?.touches ?? []
            VStack(alignment: .leading, spacing: 2) {
                if touches.isEmpty {
                    Text("Nessun tocco").foregroundStyle(.secondary)
                }
                ForEach(touches, id: \.id) { touch in
                    Text(String(format: "#%d  x %.3f  y %.3f  size %.2f  %@", touch.id, touch.x, touch.y, touch.size, String(describing: touch.phase)))
                }
            }
            .font(.caption.monospaced())
            .frame(minHeight: 60, alignment: .topLeading)
        }
    }

    private func draw(in context: inout GraphicsContext, size: CGSize) {
        let surface = CGRect(origin: .zero, size: size)
        let shape = Path(roundedRect: surface, cornerRadius: 12)
        context.fill(shape, with: .color(.secondary.opacity(0.12)))
        context.stroke(shape, with: .color(.secondary.opacity(0.4)), lineWidth: 1)

        // Edge zones: the top and bottom bands have the same physical width as the side ones.
        let zoneX = size.width * edgeWidth
        let zoneY = min(zoneX, size.height * 0.3)
        var zones = Path()
        zones.addRect(CGRect(x: 0, y: 0, width: zoneX, height: size.height))
        zones.addRect(CGRect(x: size.width - zoneX, y: 0, width: zoneX, height: size.height))
        zones.addRect(CGRect(x: 0, y: 0, width: size.width, height: zoneY))
        zones.addRect(CGRect(x: 0, y: size.height - zoneY, width: size.width, height: zoneY))
        context.clip(to: shape)
        context.fill(zones, with: .color(.accentColor.opacity(0.15)))

        for touch in frame?.touches ?? [] where touch.phase != .lifted {
            // Normalized coordinates have the origin at the bottom-left.
            let center = CGPoint(x: touch.x * size.width, y: (1 - touch.y) * size.height)
            let radius = min(max(touch.size * 10, 8), 26)
            let circle = Path(ellipseIn: CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2))
            switch touch.phase {
            case .hovering:
                context.stroke(circle, with: .color(.secondary), lineWidth: 1.5)
            case .began:
                context.fill(circle, with: .color(.green))
            case .ending:
                context.fill(circle, with: .color(.orange))
            default:
                context.fill(circle, with: .color(.accentColor))
            }
            context.draw(Text("\(touch.id)").font(.caption2.bold()).foregroundColor(.white), at: center)
        }
    }
}
