import Foundation
import Combine

class TunnelStore: ObservableObject {
    @Published var tunnels: [Tunnel] = []
    private var managers: [UUID: SSHTunnelManager] = [:]
    private var cancellables = Set<AnyCancellable>()

    private static let saveKey = "tunnelConfigs"

    init() {
        load()
        autoStartTunnels()
    }

    func add(_ config: TunnelConfig) {
        let tunnel = Tunnel(config: config)
        tunnels.append(tunnel)
        save()
    }

    func remove(_ tunnel: Tunnel) {
        disconnect(tunnel)
        tunnels.removeAll { $0.id == tunnel.id }
        save()
    }

    func update(_ tunnel: Tunnel, with config: TunnelConfig) {
        disconnect(tunnel)
        tunnel.config = config
        save()
    }

    func connect(_ tunnel: Tunnel) {
        // A previous run of the app (or a crash) can leave an untracked ssh process
        // still bound to this tunnel's local port. Without this, the new ssh process
        // fails immediately with "Address already in use" and ExitOnForwardFailure
        // kills it — which just looks like "won't connect" with no obvious cause.
        killStaleProcess(onPort: tunnel.config.localPort) { [weak self] in
            guard let self = self else { return }
            let manager = SSHTunnelManager(tunnel: tunnel)
            self.managers[tunnel.id] = manager
            manager.connect()
        }
    }

    func setAutoStart(_ tunnel: Tunnel, _ enabled: Bool) {
        guard let idx = tunnels.firstIndex(where: { $0.id == tunnel.id }) else { return }
        tunnels[idx].config.autoStart = enabled
        save()
    }

    private func autoStartTunnels() {
        for tunnel in tunnels where tunnel.config.autoStart {
            connect(tunnel)
        }
    }

    /// Finds any process listening on `port` that isn't one of our own tracked
    /// managers and kills it, then calls `completion` once the port is clear.
    private func killStaleProcess(onPort port: Int, completion: @escaping () -> Void) {
        let managedPIDs = Set(managers.values.compactMap { $0.processID })
        DispatchQueue.global().async {
            let task = Process()
            task.executableURL = URL(fileURLWithPath: "/usr/sbin/lsof")
            task.arguments = ["-nP", "-iTCP:\(port)", "-sTCP:LISTEN", "-t"]
            let pipe = Pipe()
            task.standardOutput = pipe
            task.standardError = Pipe()
            var foundStale = false
            do {
                try task.run()
                task.waitUntilExit()
                let output = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
                for pidStr in output.split(separator: "\n") {
                    guard let pid = Int32(pidStr.trimmingCharacters(in: .whitespaces)), pid > 0,
                          !managedPIDs.contains(pid) else { continue }
                    kill(pid, SIGTERM)
                    foundStale = true
                }
            } catch {
                // lsof not available or failed — fall through and let the connect attempt
                // surface any port conflict on its own.
            }
            if foundStale {
                Thread.sleep(forTimeInterval: 0.3)
            }
            DispatchQueue.main.async { completion() }
        }
    }

    func disconnect(_ tunnel: Tunnel) {
        managers[tunnel.id]?.disconnect()
        managers.removeValue(forKey: tunnel.id)
    }

    func toggleConnection(_ tunnel: Tunnel) {
        if tunnel.status.isConnected {
            disconnect(tunnel)
        } else {
            connect(tunnel)
        }
    }

    func forceDisconnect(_ tunnel: Tunnel) {
        managers[tunnel.id]?.forceDisconnect()
        managers.removeValue(forKey: tunnel.id)
    }

    func clearStale() {
        for tunnel in tunnels {
            switch tunnel.status {
            case .error:
                managers[tunnel.id]?.disconnect()
                managers.removeValue(forKey: tunnel.id)
                tunnel.log("Reset from error state by Clear Stale")
                DispatchQueue.main.async { tunnel.status = .disconnected }
            case .connected, .connecting:
                let manager = managers[tunnel.id]
                let alive = manager?.isProcessRunning ?? false
                if !alive {
                    managers.removeValue(forKey: tunnel.id)
                    tunnel.log("Detached tunnel detected — reset to disconnected")
                    DispatchQueue.main.async { tunnel.status = .disconnected }
                }
            default:
                break
            }
        }
        killOrphanedSSHTunnels()
    }

    private func killOrphanedSSHTunnels() {
        let managedPIDs = Set(managers.values.compactMap { $0.processID })

        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/pgrep")
        task.arguments = ["-f", "ssh.*ExitOnForwardFailure=yes"]
        let pipe = Pipe()
        task.standardOutput = pipe
        try? task.run()
        task.waitUntilExit()

        let output = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        for pidStr in output.components(separatedBy: "\n") {
            guard let pid = Int32(pidStr.trimmingCharacters(in: .whitespaces)),
                  pid > 0, !managedPIDs.contains(pid) else { continue }
            kill(pid, SIGKILL)
        }
    }

    private func save() {
        let configs = tunnels.map { $0.config }
        if let data = try? JSONEncoder().encode(configs) {
            UserDefaults.standard.set(data, forKey: Self.saveKey)
        }
    }

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: Self.saveKey),
              let configs = try? JSONDecoder().decode([TunnelConfig].self, from: data) else { return }
        tunnels = configs.map { Tunnel(config: $0) }
    }
}
