import SwiftUI
import AppSettings
import GestureEngine
import Permissions
import TouchInput

/// Content of the menu bar window: the main page and the settings page.
struct PanelView: View {
    enum Page {
        case main, settings
    }

    @EnvironmentObject private var coordinator: AppCoordinator
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var permissions: PermissionsManager
    @State private var page: Page

    init(initialPage: Page = .main) {
        _page = State(initialValue: initialPage)
    }

    var body: some View {
        Group {
            switch page {
            case .main: MainPage(page: $page)
            case .settings: SettingsPage(page: $page)
            }
        }
        .padding(.horizontal, 18)
        .padding(.top, 16)
        .padding(.bottom, 10)
        .frame(width: 330)
        .preferredColorScheme(settings.appearance.colorScheme)
        .onAppear {
            permissions.refresh()
            coordinator.refreshLevels()
        }
    }
}

// MARK: - Footer

struct PanelFooter<Leading: View>: View {
    @EnvironmentObject private var coordinator: AppCoordinator
    @EnvironmentObject private var settings: AppSettings
    @ViewBuilder var leading: Leading

    var body: some View {
        VStack(spacing: 8) {
            Divider()
            HStack(spacing: 6) {
                leading
                Spacer()
                Menu {
                    Button(settings.enabled ? "Metti in pausa SlideEdge" : "Riattiva SlideEdge") {
                        settings.enabled.toggle()
                    }
                    Divider()
                    Button("Visualizza tocchi…") { coordinator.showTouchDebug() }
                    Button("Permessi…") { coordinator.showOnboarding() }
                    Divider()
                    Button("Informazioni su SlideEdge") { coordinator.showAbout() }
                } label: {
                    Image(systemName: "ellipsis.circle").font(.system(size: 15))
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
                .foregroundStyle(.secondary)
                .help("Altro")
                FooterIconButton(symbol: "power", help: "Esci da SlideEdge") {
                    NSApp.terminate(nil)
                }
            }
        }
    }
}

// MARK: - Main page

private struct MainPage: View {
    @Binding var page: PanelView.Page
    @EnvironmentObject private var coordinator: AppCoordinator
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var permissions: PermissionsManager
    @EnvironmentObject private var touchMonitor: TouchMonitor
    @EnvironmentObject private var controlStatus: ControlStatus
    @EnvironmentObject private var levels: LiveLevels

    var body: some View {
        VStack(spacing: 16) {
            PanelHeader(title: "SlideEdge") { StatusBadge() }

            if !permissions.allGranted {
                PermissionBanner { coordinator.showOnboarding() }
            }

            LevelsCard(left: info(forLeft: true), right: info(forLeft: false))

            VStack(spacing: 14) {
                ToggleRow(symbol: "hand.tap.fill", title: "Feedback aptico",
                          subtitle: "Un clic a ogni scatto", isOn: $settings.haptics)
                ToggleRow(symbol: "speaker.slash.fill", title: "Muto rapido",
                          subtitle: "Doppio tap in alto a destra", isOn: $settings.quickMute)
                ToggleRow(symbol: "forward.fill", title: "Media Strip",
                          subtitle: "Swipe in basso per cambiare brano", isOn: $settings.mediaStrip)
                ToggleRow(symbol: "playpause.fill", title: "Tocca per Play/Pausa",
                          subtitle: "Doppio tap sul bordo inferiore", isOn: $settings.mediaTapPlayPause)
                    .disabled(!settings.mediaStrip)
                    .opacity(settings.mediaStrip ? 1 : 0.45)
            }

            Divider()

            VStack(spacing: 14) {
                SliderRow(symbol: "gauge.with.dots.needle.33percent", title: "Sensibilità",
                          valueText: String(format: "%.2g×", settings.sensitivity),
                          value: $settings.sensitivity, range: 0.25...3, step: 0.25)
                SliderRow(symbol: "arrow.left.and.right", title: "Larghezza bordo",
                          valueText: "\(Int((settings.edgeWidth * 100).rounded()))%",
                          value: $settings.edgeWidth, range: 0.02...0.15, step: 0.01)
            }

            PanelFooter {
                Button {
                    page = .settings
                } label: {
                    Label("Impostazioni", systemImage: "gearshape")
                        .font(.system(size: 13))
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func info(forLeft left: Bool) -> LevelInfo {
        let isVolume = left == settings.swapSides
        if isVolume {
            return LevelInfo(title: "Volume", symbol: "speaker.wave.2.fill", tint: .volumeTint,
                             value: levels.volume, muted: levels.muted)
        }
        return LevelInfo(title: "Luminosità", symbol: "sun.max.fill", tint: .brightnessTint,
                         value: controlStatus.brightness.isAvailable ? levels.brightness : nil)
    }
}

/// "Ready" / "Paused" / problem indicator. Clicking it pauses or resumes SlideEdge.
private struct StatusBadge: View {
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var permissions: PermissionsManager
    @EnvironmentObject private var touchMonitor: TouchMonitor

    var body: some View {
        Button {
            settings.enabled.toggle()
        } label: {
            HStack(spacing: 6) {
                Circle().fill(state.color).frame(width: 7, height: 7)
                Text(state.text).font(.system(size: 12))
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .foregroundStyle(.secondary)
        .help(settings.enabled ? "Metti in pausa" : "Riattiva")
    }

    private var state: (text: String, color: Color) {
        if !settings.enabled { return ("In pausa", .gray) }
        if case .unavailable = touchMonitor.status { return ("Non disponibile", .red) }
        if !permissions.allGranted { return ("Permessi", .orange) }
        if touchMonitor.devices.isEmpty { return ("Nessun trackpad", .orange) }
        return ("Pronto", .green)
    }
}

private struct PermissionBanner: View {
    let action: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
            Text("Mancano dei permessi").font(.system(size: 12, weight: .medium))
            Spacer()
            Button("Concedi", action: action).controlSize(.small)
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.orange.opacity(0.12)))
    }
}

// MARK: - Settings page

private struct SettingsPage: View {
    @Binding var page: PanelView.Page
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var controlStatus: ControlStatus
    @EnvironmentObject private var loginItem: LoginItem

    private var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—"
    }

    var body: some View {
        VStack(spacing: 14) {
            PanelHeader(title: "Impostazioni") { EmptyView() }

            ScrollView {
                VStack(spacing: 14) {
                    SectionTitle(text: "Gesti dei bordi")
                    ToggleRow(symbol: "arrow.left.arrow.right", title: "Scambia lati",
                              subtitle: settings.swapSides ? "Sx: Volume · Dx: Luminosità" : "Sx: Luminosità · Dx: Volume",
                              isOn: $settings.swapSides)
                    PanelRow(symbol: "square.bottomhalf.filled", title: "Area attiva",
                             subtitle: "Bordo sinistro, poi destro") {
                        VStack(alignment: .trailing, spacing: 4) {
                            AreaPicker(label: "Bordo sinistro", selection: $settings.leftActiveArea)
                            AreaPicker(label: "Bordo destro", selection: $settings.rightActiveArea)
                        }
                    }
                    ToggleRow(symbol: "option", title: "Richiedi Fn o ⌥",
                              subtitle: "Slide solo con il tasto premuto", isOn: $settings.requireModifier)
                    ToggleRow(symbol: "hand.raised.fill", title: "Ignora mentre scrivi",
                              subtitle: "Pausa di 0,5 s dopo ogni tasto", isOn: $settings.palmRejection)
                    ToggleRow(symbol: "light.max", title: "Retroilluminazione tastiera",
                              subtitle: controlStatus.keyboardBacklight ? "Slide sul bordo superiore" : "Non disponibile su questo Mac",
                              isOn: $settings.keyboardBacklightEdge)
                        .disabled(!controlStatus.keyboardBacklight)

                    Divider()

                    SectionTitle(text: "Durante lo slide")
                    ToggleRow(symbol: "cursorarrow", title: "Blocca cursore",
                              subtitle: "Il puntatore resta fermo", isOn: $settings.lockCursor)
                    ToggleRow(symbol: "eye.slash", title: "Nascondi cursore",
                              subtitle: "Mentre è bloccato", isOn: $settings.hideCursor)
                        .disabled(!settings.lockCursor)
                        .opacity(settings.lockCursor ? 1 : 0.45)
                    ToggleRow(symbol: "dial.low", title: "Controllo fine",
                              subtitle: "Quarti di scatto (o tieni ⇧⌥)", isOn: $settings.preciseSliding)
                    ToggleRow(symbol: "arrow.uturn.backward", title: "Inverti swipe brani",
                              subtitle: "A destra: brano precedente", isOn: $settings.reverseSwipe)

                    Divider()

                    SectionTitle(text: "Generale")
                    PanelRow(symbol: "circle.lefthalf.filled", title: "Aspetto") {
                        Picker("Aspetto", selection: $settings.appearance) {
                            ForEach(AppearanceMode.allCases) { Text($0.title).tag($0) }
                        }
                        .labelsHidden()
                        .pickerStyle(.segmented)
                        .fixedSize()
                    }
                    PanelRow(symbol: "rectangle.topthird.inset.filled", title: "Angolo in alto a sinistra",
                             subtitle: "Doppio tap") {
                        Picker("Azione", selection: $settings.cornerAction) {
                            ForEach(CornerAction.allCases) { Text($0.title).tag($0) }
                        }
                        .labelsHidden()
                        .pickerStyle(.menu)
                        .fixedSize()
                    }
                    ToggleRow(symbol: "computermouse", title: "Magic Mouse",
                              subtitle: "Usa anche i suoi bordi", isOn: $settings.magicMouse)
                    ToggleRow(symbol: "power", title: "Apri al login", isOn: Binding(
                        get: { loginItem.isEnabled },
                        set: { loginItem.set($0) }
                    ))
                }
                .padding(.trailing, 4)
            }
            .frame(height: 540)

            PanelFooter {
                Button {
                    page = .main
                } label: {
                    Label("Indietro", systemImage: "chevron.left").font(.system(size: 13))
                }
                .buttonStyle(.plain)
                Text("Versione \(version)")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .padding(.leading, 10)
            }
        }
        .onAppear { loginItem.refresh() }
    }
}

private struct AreaPicker: View {
    let label: String
    @Binding var selection: ActiveArea

    var body: some View {
        Picker(label, selection: $selection) {
            ForEach(ActiveArea.allCases) { Text($0.title).tag($0) }
        }
        .labelsHidden()
        .pickerStyle(.menu)
        .controlSize(.small)
        .fixedSize()
    }
}
