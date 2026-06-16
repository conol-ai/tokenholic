import SwiftUI

@main
enum Entry {
    static func main() {
        if CommandLine.arguments.contains("--dump") {
            DebugDump.run()
            return
        }
        if CommandLine.arguments.contains("--check-update") {
            UpdateCheckDebug.run()
            return
        }
        TokenholicApp.main()
    }
}

struct TokenholicApp: App {
    @StateObject private var model = AppModel()

    var body: some Scene {
        MenuBarExtra {
            MenuBarContentView()
                .environmentObject(model)
        } label: {
            Text(model.menubarTitle)
        }
        .menuBarExtraStyle(.window)

        Window("Tokenholic Settings", id: "settings") {
            SettingsView()
                .environmentObject(model)
        }
        .windowResizability(.contentSize)
        .defaultPosition(.center)
    }
}
