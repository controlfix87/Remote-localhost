import SwiftUI

struct TunnelFormView: View {
    var existing: TunnelConfig?
    var onSave: (TunnelConfig) -> Void
    var onCancel: () -> Void

    @State private var name = ""
    @State private var remoteHost = ""
    @State private var user = ""
    @State private var useKey = true
    @State private var password = ""
    @State private var keyPath = "~/.ssh/id_rsa"
    @State private var keyPassphrase = ""
    @State private var remotePort = "3000"
    @State private var localPort = "3000"
    @State private var sshPort = "22"
    @State private var bindHost = "127.0.0.1"
    @State private var bindHostChoice: BindHostChoice = .loopback
    @State private var customBindHost = ""
    @State private var autoStart = false

    private enum BindHostChoice: Hashable {
        case loopback, localhost, custom
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(existing == nil ? "New Tunnel" : "Edit Tunnel")
                .font(.headline)
                .padding(.bottom, 4)

            TextField("Name", text: $name)
                .textFieldStyle(.roundedBorder)
            TextField("Remote Host", text: $remoteHost)
                .textFieldStyle(.roundedBorder)
            TextField("User", text: $user)
                .textFieldStyle(.roundedBorder)

            Picker("Auth", selection: $useKey) {
                Text("SSH Key").tag(true)
                Text("Password").tag(false)
            }
            .pickerStyle(.segmented)

            if useKey {
                HStack {
                    TextField("Key Path", text: $keyPath)
                        .textFieldStyle(.roundedBorder)
                    Button("Browse") {
                        let panel = NSOpenPanel()
                        panel.canChooseFiles = true
                        panel.canChooseDirectories = false
                        panel.allowsMultipleSelection = false
                        panel.directoryURL = URL(fileURLWithPath: NSHomeDirectory() + "/.ssh")
                        panel.showsHiddenFiles = true
                        if let window = NSApp.keyWindow {
                            panel.beginSheetModal(for: window) { response in
                                if response == .OK, let url = panel.url {
                                    keyPath = url.path
                                }
                            }
                        }
                    }
                }
                SecureField("Key Passphrase (optional)", text: $keyPassphrase)
                    .textFieldStyle(.roundedBorder)
            } else {
                SecureField("Password", text: $password)
                    .textFieldStyle(.roundedBorder)
            }

            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("SSH Port").font(.system(size: 10)).foregroundColor(.secondary)
                    TextField("22", text: $sshPort)
                        .textFieldStyle(.roundedBorder)
                        .onChange(of: sshPort) { v in sshPort = v.filter(\.isNumber) }
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text("Remote Port").font(.system(size: 10)).foregroundColor(.secondary)
                    TextField("3000", text: $remotePort)
                        .textFieldStyle(.roundedBorder)
                        .onChange(of: remotePort) { v in remotePort = v.filter(\.isNumber) }
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text("Local Port").font(.system(size: 10)).foregroundColor(.secondary)
                    TextField("3000", text: $localPort)
                        .textFieldStyle(.roundedBorder)
                        .onChange(of: localPort) { v in localPort = v.filter(\.isNumber) }
                }
            }

            VStack(alignment: .leading, spacing: 2) {
                Text("Remote Bind Host").font(.system(size: 10)).foregroundColor(.secondary)
                Picker("Remote Bind Host", selection: $bindHostChoice) {
                    Text("127.0.0.1").tag(BindHostChoice.loopback)
                    Text("localhost").tag(BindHostChoice.localhost)
                    Text("Custom").tag(BindHostChoice.custom)
                }
                .labelsHidden()
                .pickerStyle(.segmented)
                .onChange(of: bindHostChoice) { choice in
                    switch choice {
                    case .loopback: bindHost = "127.0.0.1"
                    case .localhost: bindHost = "localhost"
                    case .custom: bindHost = customBindHost
                    }
                }
                if bindHostChoice == .custom {
                    TextField("e.g. 10.0.0.5 or db.internal", text: $customBindHost)
                        .textFieldStyle(.roundedBorder)
                        .onChange(of: customBindHost) { v in bindHost = v }
                }
                Text("Host the remote machine connects to for the forwarded port — usually 127.0.0.1, but use \"localhost\" or another address if the remote service resolves it differently.")
                    .font(.system(size: 9))
                    .foregroundColor(.secondary)
            }

            Toggle("Auto-start when app launches", isOn: $autoStart)
                .font(.system(size: 11))
                .toggleStyle(.checkbox)

            HStack {
                Button("Cancel", action: onCancel)
                Spacer()
                Button("Save") { save() }
                    .disabled(name.isEmpty || remoteHost.isEmpty || user.isEmpty)
                    .buttonStyle(.borderedProminent)
            }
            .padding(.top, 4)
        }
        .padding(12)
        .onAppear { populateExisting() }
    }

    private func populateExisting() {
        guard let e = existing else { return }
        name = e.name
        remoteHost = e.remoteHost
        user = e.user
        remotePort = String(e.remotePort)
        localPort = String(e.localPort)
        sshPort = String(e.sshPort)
        bindHost = e.bindHost
        autoStart = e.autoStart
        switch e.bindHost {
        case "127.0.0.1": bindHostChoice = .loopback
        case "localhost": bindHostChoice = .localhost
        default:
            bindHostChoice = .custom
            customBindHost = e.bindHost
        }
        switch e.authMethod {
        case .password(let p):
            useKey = false; password = p
        case .key(let path, let pass):
            useKey = true; keyPath = path; keyPassphrase = pass ?? ""
        }
    }

    private func save() {
        let expandedPath = (keyPath as NSString).expandingTildeInPath
        let auth: AuthMethod = useKey
            ? .key(path: expandedPath, passphrase: keyPassphrase.isEmpty ? nil : keyPassphrase)
            : .password(password)

        var config = TunnelConfig(
            name: name,
            remoteHost: remoteHost,
            user: user,
            authMethod: auth,
            sshPort: Int(sshPort) ?? 22,
            remotePort: Int(remotePort) ?? 3000,
            localPort: Int(localPort) ?? 3000,
            bindHost: bindHost.isEmpty ? "127.0.0.1" : bindHost,
            autoStart: autoStart
        )
        if let e = existing { config.id = e.id }
        onSave(config)
    }
}
