import Foundation
import NetMonCore
import ServiceManagement

private enum LoginItemFailure: LocalizedError, CustomNSError {
    case notInstalled

    static var errorDomain: String { "SSIDTrafficMonitor.LoginItem" }
    var errorCode: Int { 1 }
    var errorDescription: String? {
        L10n.text("请先将 NetMon 安装到“应用程序”，再从应用包启动。")
    }
}

@MainActor
final class LoginItemController {
    var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    func setEnabled(_ enabled: Bool) throws {
        guard isInstalledApplication else {
            throw LoginItemFailure.notInstalled
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
