import Foundation
import Network

class SSHTunnelManager {
    private var process: Process?
    private var errorPipe: Pipe?
    private var askPassScript: String?
    private weak var tunnel: Tunnel?
    /// Set when disconnect()/forceDisconnect() deliberately stops the process, so the
    /// termination handler (which fires asynchronously and would otherwise see a
    /// non-zero exit code from the kill signal) doesn't race past .disconnected and
    /// overwrite it with .error.
    private var intentionallyStopped = false

    var isProcessRunning: Bool { process?.isRunning ?? false }
    var processID: Int32? { process?.processIdentifier }

    init(tunnel: Tunnel) {
        self.tunnel = tunnel
    }

    func connect() {
        guard let tunnel = tunnel else { return }
        let config = tunnel.config

        tunnel.log("Connecting to \(config.user)@\(config.remoteHost):\(config.sshPort)…")
        DispatchQueue.main.async { tunnel.status = .connecting }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/ssh")

        var args = [
            "-N",
            "-p", "\(config.sshPort)",
            "-L", "\(config.localPort):\(config.bindHost):\(config.remotePort)",
            "-o", "StrictHostKeyChecking=no",
            "-o", "ExitOnForwardFailure=yes",
            "-o", "ServerAliveInterval=30",
            "-o", "ServerAliveCountMax=3",
            "\(config.user)@\(config.remoteHost)"
        ]

        // Build environment — inherit current env then layer SSH_ASKPASS if needed
        var env = ProcessInfo.processInfo.environment

        switch config.authMethod {
        case .key(let path, let passphrase):
            args.insert(contentsOf: ["-i", path], at: 0)
            if let pass = passphrase, !pass.isEmpty {
                if let scriptPath = writeAskPassScript(secret: pass, env: &env) {
                    tunnel.log("Using SSH_ASKPASS for key passphrase")
                    askPassScript = scriptPath
                } else {
                    tunnel.log("Failed to write askpass script for key passphrase", level: .error)
                }
            }
        case .password(let pass):
            // ssh launched as a detached Process has no controlling TTY, so it can never
            // prompt interactively for a password — it will just hang or fail with
            // "Permission denied" even though the same command works fine from a terminal.
            // SSH_ASKPASS + SSH_ASKPASS_REQUIRE=force makes ssh call our script instead of
            // prompting on the TTY, which is what makes password auth work here.
            args += ["-o", "PubkeyAuthentication=no", "-o", "PreferredAuthentications=password,keyboard-interactive"]
            if !pass.isEmpty, let scriptPath = writeAskPassScript(secret: pass, env: &env) {
                tunnel.log("Using SSH_ASKPASS for password auth")
                askPassScript = scriptPath
            } else if pass.isEmpty {
                tunnel.log("No password set for password auth — connection will likely fail", level: .error)
            } else {
                tunnel.log("Failed to write askpass script for password", level: .error)
            }
        }

        process.arguments = args
        process.environment = env
        tunnel.log("ssh \(args.joined(separator: " "))")

        let errorPipe = Pipe()
        process.standardError = errorPipe
        self.errorPipe = errorPipe

        errorPipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty,
                  let msg = String(data: data, encoding: .utf8)?
                      .trimmingCharacters(in: .whitespacesAndNewlines),
                  !msg.isEmpty
            else { return }
            self?.tunnel?.log(msg)
        }

        process.terminationHandler = { [weak self] proc in
            self?.errorPipe?.fileHandleForReading.readabilityHandler = nil
            self?.cleanupAskPass()
            DispatchQueue.main.async {
                guard let self = self, let tunnel = self.tunnel else { return }
                if self.intentionallyStopped {
                    // We killed it ourselves (disconnect/forceDisconnect already set the
                    // final status) — the kill signal makes this report a non-zero exit,
                    // but that's not a real failure, so don't let it clobber .disconnected.
                    tunnel.log("SSH process terminated")
                    return
                }
                if proc.terminationStatus != 0 {
                    tunnel.log("SSH exited with status \(proc.terminationStatus)", level: .error)
                    if case .error = tunnel.status { return }
                    tunnel.status = .error("SSH exited with status \(proc.terminationStatus)")
                } else {
                    tunnel.log("SSH process ended")
                    tunnel.status = .disconnected
                }
            }
        }

        do {
            try process.run()
            self.process = process
            tunnel.log("SSH process launched (PID \(process.processIdentifier))")

            DispatchQueue.global().asyncAfter(deadline: .now() + 2) { [weak self] in
                guard self?.process?.isRunning == true else { return }
                self?.testLocalPort(config.localPort, tunnel: tunnel)
            }
        } catch {
            cleanupAskPass()
            tunnel.log("Failed to launch SSH: \(error.localizedDescription)", level: .error)
            DispatchQueue.main.async {
                tunnel.status = .error(error.localizedDescription)
            }
        }
    }

    func disconnect() {
        intentionallyStopped = true
        errorPipe?.fileHandleForReading.readabilityHandler = nil
        process?.terminate()
        process = nil
        cleanupAskPass()
        tunnel?.log("Disconnected by user")
        DispatchQueue.main.async { [weak self] in
            self?.tunnel?.status = .disconnected
        }
    }

    func forceDisconnect() {
        intentionallyStopped = true
        errorPipe?.fileHandleForReading.readabilityHandler = nil
        if let pid = process?.processIdentifier {
            kill(pid, SIGKILL)
        }
        process = nil
        cleanupAskPass()
        tunnel?.log("SSH process force killed", level: .error)
        DispatchQueue.main.async { [weak self] in
            self?.tunnel?.status = .disconnected
        }
    }

    /// Writes a one-shot askpass helper script that echoes `secret`, wires the necessary
    /// SSH_ASKPASS environment variables into `env`, and returns the script path.
    private func writeAskPassScript(secret: String, env: inout [String: String]) -> String? {
        let scriptPath = "/tmp/rl_askpass_\(UUID().uuidString).sh"
        let script = "#!/bin/sh\necho \"$RL_ASKPASS_SECRET\"\n"
        guard (try? script.write(toFile: scriptPath, atomically: true, encoding: .utf8)) != nil else {
            return nil
        }
        try? FileManager.default.setAttributes(
            [.posixPermissions: NSNumber(value: 0o700)],
            ofItemAtPath: scriptPath
        )
        env["SSH_ASKPASS"] = scriptPath
        env["SSH_ASKPASS_REQUIRE"] = "force"
        env["DISPLAY"] = env["DISPLAY"] ?? ":0"
        env["RL_ASKPASS_SECRET"] = secret
        return scriptPath
    }

    private func cleanupAskPass() {
        if let path = askPassScript {
            try? FileManager.default.removeItem(atPath: path)
            askPassScript = nil
        }
    }

    private func testLocalPort(_ port: Int, tunnel: Tunnel) {
        tunnel.log("Testing local port \(port)…")

        guard let port16 = UInt16(exactly: port),
              let nwPort = NWEndpoint.Port(rawValue: port16) else {
            tunnel.log("Invalid port number: \(port)", level: .error)
            return
        }

        let connection = NWConnection(host: "127.0.0.1", port: nwPort, using: .tcp)

        connection.stateUpdateHandler = { [weak self] state in
            switch state {
            case .ready:
                connection.cancel()
                DispatchQueue.main.async {
                    // The user may have disconnected while this check was still in
                    // flight (it can take up to several seconds) — if the process this
                    // manager owns is gone, don't resurrect "connected" out from under
                    // that disconnect.
                    guard self?.process?.isRunning == true else { return }
                    tunnel.log("Port \(port) reachable — tunnel is active")
                    tunnel.status = .connected
                }
            case .failed(let error):
                connection.cancel()
                DispatchQueue.main.async {
                    guard self?.process?.isRunning == true else { return }
                    let msg = "Port \(port) not reachable: \(error.localizedDescription)"
                    tunnel.log(msg, level: .error)
                    if case .connecting = tunnel.status {
                        tunnel.status = .error(msg)
                    }
                }
            default:
                break
            }
        }

        connection.start(queue: .global())

        DispatchQueue.global().asyncAfter(deadline: .now() + 5) { [weak self] in
            DispatchQueue.main.async {
                guard self?.process?.isRunning == true else { return }
                guard case .connecting = tunnel.status else { return }
                connection.cancel()
                let msg = "Port \(port) not reachable after 5s"
                tunnel.log(msg, level: .error)
                tunnel.status = .error(msg)
            }
        }
    }
}
