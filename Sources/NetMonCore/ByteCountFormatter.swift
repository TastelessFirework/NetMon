import Foundation

public enum ByteCountText {
    public static func string(_ bytes: UInt64, compact: Bool = false) -> String {
        let units = ["B", "KB", "MB", "GB", "TB", "PB"]
        var value = Double(bytes)
        var index = 0
        while value >= 1024, index < units.count - 1 {
            value /= 1024
            index += 1
        }

        if index == 0 {
            return "\(bytes) B"
        }

        let digits: Int
        if compact {
            digits = value < 9.95 ? 1 : 0
        } else if value >= 100 {
            digits = 0
        } else if value >= 10 {
            digits = 1
        } else {
            digits = 2
        }
        return String(format: "%.*f %@", digits, value, units[index])
    }

    public static func speed(bytes: UInt64, interval: TimeInterval) -> String {
        guard interval > 0 else { return "0 B/s" }
        let perSecond = UInt64(min(Double(UInt64.max), Double(bytes) / interval))
        return "\(string(perSecond))/s"
    }
}
