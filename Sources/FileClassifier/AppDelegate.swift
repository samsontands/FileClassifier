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
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }

    func applicationWillTerminate(_ notification: Notification) {
        FileStaging.cleanup()
    }
}
