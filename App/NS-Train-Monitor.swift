import SwiftUI

@main struct NSTrainMonitorApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var model = MonitorModel()
    var body: some Scene {
        WindowGroup(id: "main") { RootView(model: model) }
            .windowStyle(.titleBar)
            .commands { CommandGroup(replacing: .newItem) { } }
        MenuBarExtra("NS Train Monitor", systemImage: "tram.fill") {
            MenuBarMenu(model: model)
        }
    }
}
