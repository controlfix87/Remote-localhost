import SwiftUI

private struct ContentHeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

/// Bubbles up the actual rendered height of a single tunnel row (content + its
/// own 5pt of padding) so the 4-row minimum window height can be based on the
/// real thing instead of a guessed constant.
private struct RowHeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

struct MenuBarView: View {
    @EnvironmentObject var store: TunnelStore
    /// Reports the natural height of `actualContent` whenever it changes, so the host
    /// (AppDelegate) can size the popover to match it exactly — no artificial multiplier.
    var onContentHeightChange: (CGFloat) -> Void = { _ in }

    private let minVisibleRows: CGFloat = 4
    /// Fallback used only before any row has been measured (e.g. zero tunnels).
    @State private var measuredRowHeight: CGFloat = 32

    @State private var showingAddForm = false
    @State private var editingTunnel: Tunnel? = nil
    @State private var showingAutoStartManager = false

    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
    }

    var body: some View {
        VStack(spacing: 0) {
            actualContent
                // Forces SwiftUI to compute actualContent's true intrinsic height
                // regardless of whatever size the popover currently happens to be.
                // Without this, the GeometryReader below measures the *resolved*
                // size under the current (possibly already-inflated) proposal, that
                // measurement gets fed back into popover.contentSize, which grows
                // the proposal, which grows the next measurement — an unbounded
                // feedback loop that was the actual cause of the huge gaps.
                .fixedSize(horizontal: false, vertical: true)
                .background(GeometryReader { geo in
                    Color.clear.preference(key: ContentHeightKey.self, value: geo.size.height)
                })
            // Absorbs whatever extra height the popover was given beyond the
            // content's natural size, keeping actualContent pinned to the top.
            Spacer(minLength: 0)
        }
        .onPreferenceChange(ContentHeightKey.self) { onContentHeightChange($0) }
        .onPreferenceChange(RowHeightKey.self) { if $0 > 0 { measuredRowHeight = $0 } }
        .frame(width: 380, alignment: .top)
    }

    private var actualContent: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 2) {
                HStack(spacing: 6) {
                    Text("Remote localhost")
                        .font(.headline)
                    Text(verbatim: "v\(appVersion)")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.secondary.opacity(0.15))
                        .clipShape(Capsule())
                }
                Spacer()

                Image(systemName: "xmark.circle")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
                    .padding(8)
                    .contentShape(Rectangle())
                    .help("Clear Stale")
                    .onTapGesture { store.clearStale() }

                Image(systemName: "bolt.badge.a")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
                    .padding(8)
                    .contentShape(Rectangle())
                    .help("Manage Auto-Start")
                    .onTapGesture { showingAutoStartManager = true }

                Image(systemName: "power")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
                    .padding(8)
                    .contentShape(Rectangle())
                    .help("Quit")
                    .onTapGesture { NSApp.terminate(nil) }

                Image(systemName: "plus")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.white)
                    .frame(width: 20, height: 20)
                    .background(Color.accentColor)
                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                    .contentShape(Rectangle())
                    .help("Add Tunnel")
                    .onTapGesture { showingAddForm = true }
            }
            .padding(.leading, 8)
            .padding(.trailing, 4)
            .padding(.top, 8)

            Divider()

            if showingAddForm {
                TunnelFormView(onSave: { config in
                    store.add(config)
                    showingAddForm = false
                }, onCancel: { showingAddForm = false })
            } else if let tunnel = editingTunnel {
                TunnelFormView(
                    existing: tunnel.config,
                    onSave: { config in
                        store.update(tunnel, with: config)
                        editingTunnel = nil
                    },
                    onCancel: { editingTunnel = nil }
                )
            } else if showingAutoStartManager {
                AutoStartManagerView(onClose: { showingAutoStartManager = false })
            } else {
                tunnelList
                    .frame(minHeight: measuredRowHeight * minVisibleRows, alignment: .top)
            }
        }
    }

    @ViewBuilder
    private var tunnelList: some View {
        if store.tunnels.isEmpty {
            Text("No tunnels configured")
                .foregroundColor(.secondary)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
        } else {
            // Wrapping the ForEach in its own VStack matters: a modifier applied
            // directly to a ForEach (e.g. `.frame(minHeight:)` at the call site)
            // gets distributed to every row it produces individually, not applied
            // once to the list as a whole — which was stretching each row to the
            // full 4-row minimum height instead of the list overall.
            VStack(spacing: 0) {
                ForEach(store.tunnels) { tunnel in
                    TunnelRowView(tunnel: tunnel, onEdit: { editingTunnel = $0 })
                    Divider().padding(.leading, 28)
                }
            }
        }
    }
}

struct TunnelRowView: View {
    @EnvironmentObject var store: TunnelStore
    @ObservedObject var tunnel: Tunnel
    var onEdit: (Tunnel) -> Void

    @State private var showingLogs = false
    @State private var userHidLogs = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 0) {
                // Left: full-width tappable area to connect/disconnect
                HStack(spacing: 8) {
                    Circle()
                        .fill(statusColor)
                        .frame(width: 8, height: 8)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(tunnel.config.name)
                            .font(.system(size: 12, weight: .medium))
                        Text(verbatim: "localhost:\(tunnel.config.localPort) → \(tunnel.config.remoteHost):\(tunnel.config.remotePort)")
                            .font(.system(size: 10))
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                }
                .padding(.leading, 12)
                .contentShape(Rectangle())
                .onTapGesture { store.toggleConnection(tunnel) }

                // Right: icon actions
                if isActive {
                    Image(systemName: "xmark.octagon.fill")
                        .font(.system(size: 13))
                        .foregroundColor(.red)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .contentShape(Rectangle())
                        .help("Close connection")
                        .onTapGesture { store.forceDisconnect(tunnel) }
                } else {
                    Image(systemName: "play.circle.fill")
                        .font(.system(size: 13))
                        .foregroundColor(.accentColor)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .contentShape(Rectangle())
                        .help("Connect")
                        .onTapGesture { store.connect(tunnel) }
                }

                Image(systemName: "ladybug")
                    .font(.system(size: 11))
                    .foregroundColor(!isActive ? .secondary.opacity(0.4) : (hasErrorLog ? .red : .secondary))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .contentShape(Rectangle())
                    .help(isActive ? (hasErrorLog ? "Debug (errors)" : "Debug") : "Debug (no active connection)")
                    .allowsHitTesting(isActive)
                    .onTapGesture {
                        showingLogs.toggle()
                        userHidLogs = !showingLogs
                    }

                Menu {
                    Button(tunnel.config.autoStart ? "Disable Auto-Start" : "Enable Auto-Start") {
                        store.setAutoStart(tunnel, !tunnel.config.autoStart)
                    }
                    Button("Edit") { onEdit(tunnel) }
                    Divider()
                    Button("Delete", role: .destructive) { store.remove(tunnel) }
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .font(.system(size: 11))
                        .foregroundColor(hasErrorLog ? .red : .secondary)
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .frame(width: 22)
                .padding(.trailing, 8)
            }
            // The 5pt of extra spacing around the row's natural content height.
            .padding(.vertical, 2.5)
            .background(GeometryReader { geo in
                Color.clear.preference(key: RowHeightKey.self, value: geo.size.height)
            })
            .onChange(of: tunnel.status) { newStatus in
                switch newStatus {
                case .connecting:
                    if !userHidLogs { showingLogs = true }
                case .connected:
                    // A successful connection needs no further watching — collapse the logs.
                    showingLogs = false
                    userHidLogs = false
                default:
                    userHidLogs = false
                }
            }

            if showingLogs {
                logPanel
                    .padding(.horizontal, 12)
                    .padding(.bottom, 6)
            }
        }
    }

    private var isActive: Bool {
        switch tunnel.status {
        case .connected, .connecting: return true
        default: return false
        }
    }

    private var logPanel: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Logs")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(.secondary)
                Spacer()
                Text("Clear")
                    .font(.system(size: 10))
                    .foregroundColor(.accentColor)
                    .padding(.vertical, 2)
                    .padding(.horizontal, 4)
                    .contentShape(Rectangle())
                    .onTapGesture { tunnel.clearLogs() }
            }
            .padding(.horizontal, 6)
            .padding(.top, 4)
            .padding(.bottom, 2)

            Divider()

            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 1) {
                        if tunnel.logs.isEmpty {
                            Text("No logs yet")
                                .font(.system(size: 10))
                                .foregroundColor(.secondary)
                                .padding(6)
                        } else {
                            ForEach(tunnel.logs) { entry in
                                HStack(alignment: .top, spacing: 4) {
                                    Text(verbatim: timeString(entry.date))
                                        .font(.system(size: 9, design: .monospaced))
                                        .foregroundColor(.secondary)
                                        .fixedSize()
                                    Text(entry.message)
                                        .font(.system(size: 10, design: .monospaced))
                                        .foregroundColor(entry.level == .error ? .red : .primary)
                                        .textSelection(.enabled)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                }
                                .padding(.horizontal, 6)
                                .padding(.vertical, 1)
                                .id(entry.id)
                            }
                        }
                    }
                }
                .frame(maxHeight: 120)
                .onChange(of: tunnel.logs.count) { _ in
                    if let last = tunnel.logs.last {
                        proxy.scrollTo(last.id, anchor: .bottom)
                    }
                }
            }
        }
        .background(Color(NSColor.textBackgroundColor).opacity(0.8))
        .cornerRadius(4)
    }

    private var hasErrorLog: Bool {
        tunnel.logs.contains { $0.level == .error }
    }

    private func timeString(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss"
        return f.string(from: date)
    }

    private var statusColor: Color {
        switch tunnel.status {
        case .connected: return .green
        case .connecting: return .yellow
        case .disconnected: return .red
        case .error: return .orange
        }
    }
}
