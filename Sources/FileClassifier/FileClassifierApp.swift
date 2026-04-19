import SwiftUI

struct FileClassifierApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        WindowGroup("File Classifier") {
            ContentView()
                .frame(minWidth: 480, minHeight: 360)
        }
        .windowResizability(.contentSize)
        .commands {
            CommandGroup(replacing: .newItem) {}
        }
    }
}
