import SwiftUI
import Permissions

struct OnboardingView: View {
    @EnvironmentObject private var permissions: PermissionsManager
    let onDone: () -> Void

    var body: some View {
        VStack(spacing: 18) {
            Image(systemName: "rectangle.and.hand.point.up.left")
                .font(.system(size: 44))
                .foregroundStyle(.tint)

            VStack(spacing: 6) {
                Text("Benvenuto in SlideEdge").font(.title2.bold())
                Text("Per trasformare i bordi del trackpad in controlli servono due permessi. Nessun dato lascia il Mac.")
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            VStack(spacing: 12) {
                PermissionCard(
                    permission: .accessibility,
                    title: "Accessibilità",
                    detail: "Serve per inviare i tasti di volume, luminosità e multimediali e per bloccare il cursore durante lo slide. Sulle versioni recenti di macOS può comparire come “Device Control and Data Access”."
                )
                PermissionCard(
                    permission: .inputMonitoring,
                    title: "Monitoraggio input",
                    detail: "Serve per la palm rejection: SlideEdge registra solo l'istante in cui premi un tasto, mai quale tasto."
                )
            }

            HStack {
                Button("Più tardi", action: onDone)
                Spacer()
                Button("Continua", action: onDone)
                    .keyboardShortcut(.defaultAction)
                    .disabled(!permissions.allGranted)
            }
        }
        .padding(24)
        .frame(width: 460)
    }
}

private struct PermissionCard: View {
    @EnvironmentObject private var permissions: PermissionsManager
    let permission: Permission
    let title: String
    let detail: String

    var body: some View {
        let granted = permissions.isGranted(permission)
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: granted ? "checkmark.circle.fill" : "circle.dashed")
                .font(.title2)
                .foregroundStyle(granted ? .green : .secondary)
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.headline)
                Text(detail)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                if !granted {
                    Button("Apri Impostazioni di Sistema") { permissions.request(permission) }
                        .controlSize(.small)
                        .padding(.top, 2)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 10))
    }
}
