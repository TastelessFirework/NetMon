import Foundation
import Testing
@testable import NetMonCore

@Suite("All-network usage totals")
struct NetworkUsageTotalsTests {
    private func summary(
        key: String,
        kind: NetworkKind,
        today: UsageAmount,
        recent: UsageAmount,
        month: UsageAmount,
        allTime: UsageAmount
    ) -> NetworkSummary {
        NetworkSummary(
            identity: NetworkIdentity(
                key: key, displayName: key, ssid: nil,
                kind: kind, interfaceName: key
            ),
            today: today, recentSevenDays: recent, month: month,
            allTime: allTime, firstSeen: Date(timeIntervalSince1970: 0),
            lastUsed: Date(timeIntervalSince1970: 0)
        )
    }

    @Test("Each period and direction includes all recorded network kinds")
    func sumsAllNetworks() {
        let summaries = NetworkKind.allCases.enumerated().map { index, kind in
            let value = UInt64(index + 1)
            return summary(
                key: kind.rawValue, kind: kind,
                today: UsageAmount(download: value, upload: value * 2),
                recent: UsageAmount(download: value * 3, upload: value * 4),
                month: UsageAmount(download: value * 5, upload: value * 6),
                allTime: UsageAmount(download: value * 7, upload: value * 8)
            )
        }
        let totals = NetworkUsageTotals(summaries: summaries)
        #expect(totals.today == UsageAmount(download: 15, upload: 30))
        #expect(totals.recentSevenDays == UsageAmount(download: 45, upload: 60))
        #expect(totals.month == UsageAmount(download: 75, upload: 90))
        #expect(totals.allTime == UsageAmount(download: 105, upload: 120))
        #expect(totals.allTime.total == 225)
    }

    @Test("An empty history displays zero for every period")
    func emptyHistory() {
        let totals = NetworkUsageTotals(summaries: [])
        #expect(totals.today == UsageAmount())
        #expect(totals.recentSevenDays == UsageAmount())
        #expect(totals.month == UsageAmount())
        #expect(totals.allTime == UsageAmount())
    }

    @Test("Large totals saturate without wrapping or mixing directions")
    func overflow() {
        let totals = NetworkUsageTotals(summaries: [
            summary(
                key: "a", kind: .wifi,
                today: UsageAmount(download: .max, upload: 3),
                recent: UsageAmount(download: 4, upload: .max),
                month: UsageAmount(download: .max, upload: .max),
                allTime: UsageAmount(download: .max - 1, upload: 2)
            ),
            summary(
                key: "b", kind: .ethernet,
                today: UsageAmount(download: 1, upload: 5),
                recent: UsageAmount(download: 6, upload: 1),
                month: UsageAmount(download: 1, upload: 1),
                allTime: UsageAmount(download: 2, upload: 7)
            ),
        ])
        #expect(totals.today == UsageAmount(download: .max, upload: 8))
        #expect(totals.recentSevenDays == UsageAmount(download: 10, upload: .max))
        #expect(totals.month == UsageAmount(download: .max, upload: .max))
        #expect(totals.allTime == UsageAmount(download: .max, upload: 9))
        #expect(totals.allTime.total == .max)
    }
}
