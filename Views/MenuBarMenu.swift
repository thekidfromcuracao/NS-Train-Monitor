import SwiftUI
import AppKit

struct MenuBarMenu: View {
    @ObservedObject var model: MonitorModel
    @Environment(\.openWindow) private var openWindow
    var body: some View {
        Button("Open NS Train Monitor") {
            NSApp.setActivationPolicy(.regular)
            if let window = NSApp.windows.first(where: {
                ($0.isVisible || $0.isMiniaturized) && $0.canBecomeKey && !($0 is NSPanel)
            }) {
                if window.isMiniaturized { window.deminiaturize(nil) }
                window.makeKeyAndOrderFront(nil)
            } else {
                openWindow(id: "main")
            }
            NSApp.activate(ignoringOtherApps: true)
        }
        Divider()
        Text(model.running.isEmpty ? "No active monitors" : "\(model.running.count) active monitor\(model.running.count == 1 ? "" : "s")")
        Divider()
        Button("Quit NS Train Monitor") { NSApp.terminate(nil) }
            .keyboardShortcut("q")
    }
}
#Preview {
    VStack(alignment: .leading, spacing: 12) {
        MenuBarMenu(model: MonitorModel())
    }
    .padding()
    .frame(width: 280)
}


