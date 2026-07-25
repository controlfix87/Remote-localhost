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
- Per-tunnel auto-start on app launch, with a dedicated manager view to toggle several at once.
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
4. Use the bolt icon to open the Auto-Start manager and control which tunnels reconnect automatically on launch.

## Architecture

The app is a single-target SwiftUI menu bar app (no window, just an `NSStatusItem` + `NSPopover`) with no external dependencies.

| File | Responsibility |
|---|---|
| `RemoteLocalhostApp.swift` | App entry point. `AppDelegate` owns the status bar item and popover (SwiftUI's `MenuBarExtra` isn't used — a manually managed `NSPopover` gives precise control over content-driven sizing). |
| `TunnelConfig.swift` | Data model: `TunnelConfig` (persisted, `Codable`), `AuthMethod` (key vs. password), `TunnelStatus`, and the `Tunnel` observable object wrapping a config with live status/logs. |
| `TunnelStore.swift` | Source of truth for the tunnel list. Owns one `SSHTunnelManager` per connected tunnel, persists configs to `UserDefaults`, and handles stale/orphaned-process cleanup. |
| `SSHTunnelManager.swift` | Wraps a single `/usr/bin/ssh -N -L ...` `Process`, including `SSH_ASKPASS`-based non-interactive auth and a post-connect TCP reachability check on the local port. |
| `MenuBarView.swift` | The popover UI: tunnel list, per-row status/logs/actions, and the height-measurement plumbing that sizes the popover to its actual content. |
| `TunnelFormView.swift` | Add/edit form for a single tunnel. |
| `AutoStartManagerView.swift` | Bulk view for toggling which tunnels auto-connect at launch. |

### Notable implementation details

- **Non-interactive SSH auth**: a `Process` has no controlling TTY, so `ssh` can never prompt for a password/passphrase interactively. `SSHTunnelManager` works around this by writing a one-shot, `0700`-permissioned shell script to `/tmp` that echoes the secret, and pointing `SSH_ASKPASS`/`SSH_ASKPASS_REQUIRE=force` at it. The script is deleted as soon as the process terminates.
- **Stale port/process recovery**: before connecting, `TunnelStore` shells out to `lsof` to find and kill anything already listening on the target local port (leftover from a crash or previous run), since `ExitOnForwardFailure=yes` would otherwise make a fresh connection fail immediately with "Address already in use". "Clear Stale" additionally `pgrep`s for orphaned `ssh ... ExitOnForwardFailure=yes` processes not tracked by any manager and kills them.
- **Popover self-sizing**: `MenuBarView` measures its own content height via a `GeometryReader`/`PreferenceKey` and feeds it back to `AppDelegate`, which resizes the `NSPopover` to match exactly — avoiding both clipped content and dead space. `NSHostingController.sizingOptions` is deliberately cleared to prevent a feedback loop where SwiftUI's own auto-resizing fights the explicit size.
- **Status races**: disconnects set `intentionallyStopped` before killing the SSH process so the async `terminationHandler` (which sees a non-zero exit from the kill signal) doesn't overwrite an already-correct `.disconnected` status with a spurious `.error`.

## Notes

- SSH is invoked with `StrictHostKeyChecking=no` for convenience when connecting to hosts you already trust.
- Passwords and key passphrases are written briefly to a one-shot, `0700`-permissioned `SSH_ASKPASS` script in `/tmp` for the duration of the connection attempt and removed afterward.
- Tunnel configs, including passwords/passphrases, are currently saved in plaintext via `UserDefaults`. Prefer SSH key auth where possible if that's a concern.
