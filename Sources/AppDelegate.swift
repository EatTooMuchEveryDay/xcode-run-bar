import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let store = WorkspaceStore()
    private let xcode = XcodeIntegration()
    private lazy var controller = StatusController(store: store, xcode: xcode)

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        controller.start()
    }
}
