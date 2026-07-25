import SwiftUI

@main
struct RemoteLocalhostApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        Settings { EmptyView() }
    }
}

class AppDelegate: NSObject, NSApplicationDelegate, NSPopoverDelegate {
    var statusItem: NSStatusItem!
    var popover: NSPopover!
    let tunnelStore = TunnelStore()

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "globe.badge.chevron.backward", accessibilityDescription: "Remote localhost")
            button.action = #selector(togglePopover)
            button.target = self
        }

        popover = NSPopover()
        popover.contentSize = NSSize(width: 380, height: 200)
        popover.behavior = .applicationDefined
        popover.delegate = self

        let hosting = NSHostingController(
            rootView: MenuBarView(onContentHeightChange: { [weak self] height in
                guard let self = self, height > 0 else { return }
                let size = NSSize(width: 380, height: height)
                if self.popover.contentSize != size {
                    self.popover.contentSize = size
                }
            }).environmentObject(tunnelStore)
        )
        // Disable NSHostingController's automatic content-driven resizing so our
        // explicit, measured size above is the sole source of truth for the popover size.
        hosting.sizingOptions = []
        popover.contentViewController = hosting
    }

    @objc func togglePopover() {
        guard let button = statusItem.button else { return }
        if popover.isShown {
            popover.performClose(nil)
        } else {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    func popoverDidShow(_ notification: Notification) {
        NSApp.activate(ignoringOtherApps: true)
        popover.contentViewController?.view.window?.makeKeyAndOrderFront(nil)
    }
}
