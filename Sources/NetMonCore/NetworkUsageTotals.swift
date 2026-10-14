import Foundation

/// Sums recorded usage across every network without changing attribution.
public struct NetworkUsageTotals: Equatable, Sendable {
    public private(set) var today = UsageAmount()
    public private(set) var recentSevenDays = UsageAmount()
    public private(set) var month = UsageAmount()
    public private(set) var allTime = UsageAmount()

    public init(summaries: [NetworkSummary]) {
        for summary in summaries {
            today = Self.add(today, summary.today)
            recentSevenDays = Self.add(recentSevenDays, summary.recentSevenDays)
            month = Self.add(month, summary.month)
            allTime = Self.add(allTime, summary.allTime)
        }
    }

    private static func add(_ lhs: UsageAmount, _ rhs: UsageAmount) -> UsageAmount {
        UsageAmount(
            download: saturatedAdd(lhs.download, rhs.download),
            upload: saturatedAdd(lhs.upload, rhs.upload)
        )
    }

    private static func saturatedAdd(_ lhs: UInt64, _ rhs: UInt64) -> UInt64 {
        let result = lhs.addingReportingOverflow(rhs)
        return result.overflow ? UInt64.max : result.partialValue
    }
}
