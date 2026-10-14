import Foundation
import OSLog

final class DebugLogger {
    private let logger = Logger(
        subsystem: "com.eric.SSIDTrafficMonitor",
        category: "sampling"
    )
    private let defaults = UserDefaults.standard
    private let enabledKey = "debugLogging"

    var isEnabled: Bool {
        get { defaults.bool(forKey: enabledKey) }
        set { defaults.set(newValue, forKey: enabledKey) }
    }

    var fileURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Logs/SSIDTrafficMonitor", isDirectory: true)
            .appendingPathComponent("debug.log")
    }

    func log(_ message: String) {
        // Network names and sampling details must not be public OSLog fields.
        logger.debug("\(message, privacy: .private)")
        guard isEnabled else { return }
        let line = "[\(Self.timestamp.string(from: Date()))] \(message)\n"
        print(line, terminator: "")
        do {
            try FileManager.default.createDirectory(
                at: fileURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            let data = Data(line.utf8)
            if FileManager.default.fileExists(atPath: fileURL.path) {
                let handle = try FileHandle(forWritingTo: fileURL)
                try handle.seekToEnd()
                try handle.write(contentsOf: data)
                try handle.close()
            } else {
                try data.write(to: fileURL, options: .atomic)
            }
        } catch {
            logger.error("Failed to write debug log: \(error.localizedDescription, privacy: .private)")
        }
    }

    private static let timestamp: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"
        return formatter
    }()
}
