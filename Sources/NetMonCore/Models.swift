import Foundation

public enum NetworkKind: String, Codable, CaseIterable, Sendable {
    case wifi
    case ethernet
    case ppp
    case vpn
    case other

    public var displayName: String {
        switch self {
        case .wifi: return "Wi-Fi"
        case .ethernet: return "Ethernet"
        case .ppp: return "PPP"
        case .vpn: return "VPN"
        case .other: return "其他"
        }
    }

    public var supportsCustomName: Bool {
        switch self {
        case .wifi, .ethernet, .ppp:
            return true
        case .vpn, .other:
            return false
        }
    }
}

public struct NetworkIdentity: Codable, Equatable, Hashable, Sendable {
    public let key: String
    public let displayName: String
    public let ssid: String?
    public let kind: NetworkKind
    public let interfaceName: String

    public init(
        key: String,
        displayName: String,
        ssid: String?,
        kind: NetworkKind,
        interfaceName: String
    ) {
        self.key = key
        self.displayName = displayName
        self.ssid = ssid
        self.kind = kind
        self.interfaceName = interfaceName
    }
}

public struct InterfaceCounters: Equatable, Sendable {
    public let received: UInt64
    public let transmitted: UInt64

    public init(received: UInt64, transmitted: UInt64) {
        self.received = received
        self.transmitted = transmitted
    }
}

public struct UsageAmount: Equatable, Sendable {
    public var download: UInt64
    public var upload: UInt64

    public init(download: UInt64 = 0, upload: UInt64 = 0) {
        self.download = download
        self.upload = upload
    }

    public var total: UInt64 {
        download.addingReportingOverflow(upload).overflow
            ? UInt64.max
            : download + upload
    }
}

public struct NetworkSummary: Identifiable, Equatable, Sendable {
    public var id: String { identity.key }
    public let identity: NetworkIdentity
    public var today: UsageAmount
    public var recentSevenDays: UsageAmount
    public var month: UsageAmount
    public var allTime: UsageAmount
    public let firstSeen: Date
    public var lastUsed: Date

    public init(
        identity: NetworkIdentity,
        today: UsageAmount,
        recentSevenDays: UsageAmount,
        month: UsageAmount,
        allTime: UsageAmount,
        firstSeen: Date,
        lastUsed: Date
    ) {
        self.identity = identity
        self.today = today
        self.recentSevenDays = recentSevenDays
        self.month = month
        self.allTime = allTime
        self.firstSeen = firstSeen
        self.lastUsed = lastUsed
    }
}

public struct UsageRecord: Sendable {
    public let identity: NetworkIdentity
    public let day: String
    public let amount: UsageAmount
    public let timestamp: Date

    public init(
        identity: NetworkIdentity,
        day: String,
        amount: UsageAmount,
        timestamp: Date
    ) {
        self.identity = identity
        self.day = day
        self.amount = amount
        self.timestamp = timestamp
    }
}

public enum DayKey {
    public static func string(for date: Date, calendar: Calendar = .current) -> String {
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        return String(
            format: "%04d-%02d-%02d",
            components.year ?? 1970,
            components.month ?? 1,
            components.day ?? 1
        )
    }

    public static func recentSevenStart(
        for date: Date,
        calendar: Calendar = .current
    ) -> String {
        let start = calendar.startOfDay(for: date)
        let result = calendar.date(byAdding: .day, value: -6, to: start) ?? start
        return string(for: result, calendar: calendar)
    }

    public static func monthStart(
        for date: Date,
        calendar: Calendar = .current
    ) -> String {
        let components = calendar.dateComponents([.year, .month], from: date)
        let result = calendar.date(from: components) ?? date
        return string(for: result, calendar: calendar)
    }
}
