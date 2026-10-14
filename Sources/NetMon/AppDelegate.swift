import AppKit

@main
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusMenuController: StatusMenuController?

    static func main() {
        let application = NSApplication.shared
        let delegate = AppDelegate()
        application.delegate = delegate
        application.setActivationPolicy(.accessory)
        application.run()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        let model = AppModel.shared
        model.start()

        let controller = StatusMenuController(model: model)
        controller.start()
        statusMenuController = controller
    }

    func applicationWillTerminate(_ notification: Notification) {
        statusMenuController?.stop()
        AppModel.shared.stop()
    }
}
