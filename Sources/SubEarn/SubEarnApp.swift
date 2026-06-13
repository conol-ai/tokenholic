import SwiftUI

@main
enum Entry {
    static func main() {
        if CommandLine.arguments.contains("--dump") {
            DebugDump.run()
            return
        }
        SubEarnApp.main()
    }
}

struct SubEarnApp: App {
    @StateObject private var model = AppModel()

    var body: some Scene {
        MenuBarExtra {
            MenuBarContentView()
                .environmentObject(model)
        } label: {
            Text(model.menubarTitle)
        }
        .menuBarExtraStyle(.window)
    }
}
