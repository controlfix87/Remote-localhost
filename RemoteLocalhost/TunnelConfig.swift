import Foundation

enum AuthMethod: Codable, Hashable {
    case password(String)
    case key(path: String, passphrase: String?)
}

struct TunnelConfig: Identifiable, Codable, Hashable {
    var id = UUID()
    var name: String
    var remoteHost: String
    var user: String
    var authMethod: AuthMethod
    var sshPort: Int
    var remotePort: Int
    var localPort: Int
    /// The host, as seen from the *remote* machine, that the forwarded port should connect to.
    /// Usually "127.0.0.1" or "localhost", but can be any host reachable from the remote side.
    var bindHost: String = "127.0.0.1"
    /// When true, this tunnel connects automatically when the app launches.
    var autoStart: Bool = false

    init(id: UUID = UUID(), name: String, remoteHost: String, user: String, authMethod: AuthMethod,
         sshPort: Int, remotePort: Int, localPort: Int, bindHost: String = "127.0.0.1", autoStart: Bool = false) {
        self.id = id
        self.name = name
        self.remoteHost = remoteHost
        self.user = user
        self.authMethod = authMethod
        self.sshPort = sshPort
        self.remotePort = remotePort
        self.localPort = localPort
        self.bindHost = bindHost
        self.autoStart = autoStart
    }

    // Custom decoding so tunnels saved before `bindHost` existed still load instead of
    // failing JSONDecoder entirely (which would silently wipe out saved tunnels).
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        remoteHost = try c.decode(String.self, forKey: .remoteHost)
        user = try c.decode(String.self, forKey: .user)
        authMethod = try c.decode(AuthMethod.self, forKey: .authMethod)
        sshPort = try c.decode(Int.self, forKey: .sshPort)
        remotePort = try c.decode(Int.self, forKey: .remotePort)
        localPort = try c.decode(Int.self, forKey: .localPort)
        bindHost = try c.decodeIfPresent(String.self, forKey: .bindHost) ?? "127.0.0.1"
        autoStart = try c.decodeIfPresent(Bool.self, forKey: .autoStart) ?? false
    }
}

enum TunnelStatus: Equatable {
    case disconnected, connecting, connected, error(String)

    var isConnected: Bool {
        if case .connected = self { return true }
        return false
    }
}

struct TunnelLogEntry: Identifiable {
    let id = UUID()
    let date: Date
    let message: String
    let level: Level

    enum Level: Equatable { case info, error }
}

class Tunnel: ObservableObject, Identifiable {
    let id: UUID
    @Published var config: TunnelConfig
    @Published var status: TunnelStatus = .disconnected
    @Published var logs: [TunnelLogEntry] = []

    init(config: TunnelConfig) {
        self.id = config.id
        self.config = config
    }

    func log(_ message: String, level: TunnelLogEntry.Level = .info) {
        let entry = TunnelLogEntry(date: Date(), message: message, level: level)
        DispatchQueue.main.async { self.logs.append(entry) }
    }

    func clearLogs() {
        DispatchQueue.main.async { self.logs.removeAll() }
    }
}
