import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var closeObserver: NSObjectProtocol?
    private func installApplicationIcon() {
        if let iconURL = Bundle.main.url(forResource: "AppIcon", withExtension: "icns"),
           let icon = NSImage(contentsOf: iconURL) {
            NSApp.applicationIconImage = icon
        }
    }
    func applicationWillFinishLaunching(_ notification: Notification) {
        installApplicationIcon()
    }
    func applicationDidFinishLaunching(_ notification: Notification) {
        installApplicationIcon()
        closeObserver = NotificationCenter.default.addObserver(forName: NSWindow.willCloseNotification, object: nil, queue: .main) { notification in
            guard let closingWindow = notification.object as? NSWindow, !(closingWindow is NSPanel) else { return }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                let hasAnotherMainWindow = NSApp.windows.contains {
                    $0 !== closingWindow && $0.isVisible && $0.canBecomeKey && !($0 is NSPanel)
                }
                if !hasAnotherMainWindow {
                    NSApp.setActivationPolicy(.accessory)
                }
            }
        }
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
    deinit { if let closeObserver { NotificationCenter.default.removeObserver(closeObserver) } }
}
