import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)

        // Register the Services provider so Finder's right-click menu can
        // route selections to `ServiceProvider.renameFiles(_:userData:error:)`.
        // `NSUpdateDynamicServices` forces `pbs` to re-read our Info.plist —
        // otherwise the menu item may not appear until re-login on first run.
        NSApp.servicesProvider = ServiceProvider.shared
        NSUpdateDynamicServices()

        // Belt-and-braces: even if Launch Services hasn't picked up the
        // bundled .icns yet (common on the first install of a fresh build),
        // force the Dock tile to our icon image at runtime.
        if let iconURL = Bundle.main.url(forResource: "AppIcon", withExtension: "icns"),
           let icon = NSImage(contentsOf: iconURL) {
            NSApp.applicationIconImage = icon
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }

    func applicationWillTerminate(_ notification: Notification) {
        FileStaging.cleanup()
    }
}
