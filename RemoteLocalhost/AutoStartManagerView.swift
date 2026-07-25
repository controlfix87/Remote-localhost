import SwiftUI

/// Central place to see and toggle which tunnels auto-connect when the app launches,
/// without having to open each tunnel's edit form individually.
struct AutoStartManagerView: View {
    @EnvironmentObject var store: TunnelStore
    var onClose: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Auto-Start Connections")
                    .font(.headline)
                Spacer()
                Text("Done")
                    .font(.system(size: 12))
                    .foregroundColor(.accentColor)
                    .contentShape(Rectangle())
                    .onTapGesture { onClose() }
            }
            .padding(.horizontal, 12)
            .padding(.top, 8)
            .padding(.bottom, 4)

            Text("Enabled tunnels connect automatically whenever the app starts.")
                .font(.system(size: 10))
                .foregroundColor(.secondary)
                .padding(.horizontal, 12)
                .padding(.bottom, 6)

            Divider()

            if store.tunnels.isEmpty {
                Text("No tunnels configured")
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
            } else {
                VStack(spacing: 0) {
                    ForEach(store.tunnels) { tunnel in
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(tunnel.config.name)
                                    .font(.system(size: 13, weight: .medium))
                                Text(verbatim: "localhost:\(tunnel.config.localPort) → \(tunnel.config.remoteHost):\(tunnel.config.remotePort)")
                                    .font(.system(size: 11))
                                    .foregroundColor(.secondary)
                            }
                            Spacer(minLength: 12)
                            Toggle("", isOn: Binding(
                                get: { tunnel.config.autoStart },
                                set: { store.setAutoStart(tunnel, $0) }
                            ))
                            .labelsHidden()
                            .toggleStyle(.switch)
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        Divider().padding(.leading, 16)
                    }
                }
            }
        }
    }
}
