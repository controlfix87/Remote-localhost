# Remote localhost

A lightweight macOS menu bar app for managing local SSH port-forwarding tunnels — the GUI equivalent of running:

```
ssh -N -L <localPort>:<bindHost>:<remotePort> <user>@<remoteHost> -p <sshPort>
```

without having to keep a terminal window open.

## Features

- Menu bar only — no dock icon, no main window clutter.
- Manage multiple named tunnels, each with its own host, ports, and credentials.
- Authenticate with an SSH key (with optional passphrase) or a password, supplied non-interactively via a generated `SSH_ASKPASS` helper so tunnels connect without any terminal prompts.
- Configurable remote bind host per tunnel — `127.0.0.1`, `localhost`, or any custom address the remote machine can reach, instead of an address hardcoded to `127.0.0.1`.
- Live status per tunnel (disconnected / connecting / connected / error) with a local port reachability check after connecting.
- Per-tunnel log view for SSH output, useful for debugging auth or forwarding failures.
- "Clear Stale" cleans up tunnels whose SSH process died unexpectedly and kills orphaned SSH processes left behind by previous runs.
- Tunnel configs persist across launches (saved to `UserDefaults`).

## Requirements

- macOS 13.0+
- Xcode 15+ (or newer) to build

## Building

1. Open `RemoteLocalhost.xcodeproj` in Xcode.
2. Select the `RemoteLocalhost` scheme.
3. **Run** (`Product > Run`) for a development build, or **Archive** (`Product > Archive`) to produce a Release build you can export to `/Applications`.

## Usage

1. Launch the app — its icon (a globe) appears in the menu bar.
2. Click the icon, then the `+` button to add a tunnel: name, remote host, user, auth method (key or password), SSH/remote/local ports, and remote bind host.
3. Click a tunnel to connect/disconnect. Status and logs update live in the popover.

## Notes

- SSH is invoked with `StrictHostKeyChecking=no` for convenience when connecting to hosts you already trust.
- Passwords and key passphrases are written briefly to a one-shot, `0700`-permissioned `SSH_ASKPASS` script in `/tmp` for the duration of the connection attempt and removed afterward.
- Tunnel configs, including passwords/passphrases, are currently saved in plaintext via `UserDefaults`. Prefer SSH key auth where possible if that's a concern.
# Remote-localhost
# Remote-localhost
