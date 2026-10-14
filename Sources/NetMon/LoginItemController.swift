import Foundation
import ServiceManagement

@MainActor
final class LoginItemController {
    var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    func setEnabled(_ enabled: Bool) throws {
        guard isInstalledApplication else {
            throw NSError(
                domain: "SSIDTrafficMonitor.LoginItem",
                code: 1,
                userInfo: [
                    NSLocalizedDescriptionKey:
                        "请先用 make install 安装并从 .app 启动。"
                ]
            )
        }
        if enabled {
            try SMAppService.mainApp.register()
        } else {
            try SMAppService.mainApp.unregister()
        }
    }

    private var isInstalledApplication: Bool {
        let bundleURL = Bundle.main.bundleURL.standardizedFileURL
        guard bundleURL.pathExtension == "app" else { return false }
        let systemApplications = URL(fileURLWithPath: "/Applications", isDirectory: true)
        let userApplications = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Applications", isDirectory: true)
        return bundleURL.path.hasPrefix(systemApplications.path + "/") ||
            bundleURL.path.hasPrefix(userApplications.path + "/")
    }
}
