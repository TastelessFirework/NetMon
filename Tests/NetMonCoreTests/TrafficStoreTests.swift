import Foundation
import Testing
@testable import NetMonCore

@Suite("SQLite persistence and summaries")
struct TrafficStoreTests {
    @Test("Daily, seven-day, month, and all-time totals")
    func dateAggregation() throws {
        let context = try TestContext()
        defer { context.cleanUp() }
        let store = try context.makeStore()
        let identity = makeIdentity("Home-WiFi")
        let reference = context.date(2026, 10, 6)

        try store.record([
            record(identity, day: "2026-10-06", down: 300, up: 30, at: reference),
            record(identity, day: "2026-10-01", down: 200, up: 20, at: context.date(2026, 10, 1)),
            record(identity, day: "2026-09-20", down: 100, up: 10, at: context.date(2026, 9, 20))
        ])

        let summary = try #require(
            store.fetchSummaries(
                referenceDate: reference,
                calendar: context.calendar
            ).first
        )
        #expect(summary.today == UsageAmount(download: 300, upload: 30))
        #expect(summary.recentSevenDays == UsageAmount(download: 500, upload: 50))
        #expect(summary.month == UsageAmount(download: 500, upload: 50))
        #expect(summary.allTime == UsageAmount(download: 600, upload: 60))
    }

    @Test("Networks are separated by SSID")
    func separateNetworks() throws {
        let context = try TestContext()
        defer { context.cleanUp() }
        let store = try context.makeStore()
        let home = makeIdentity("Home-WiFi")
        let office = makeIdentity("Office-WiFi")
        let now = context.date(2026, 10, 6)

        try store.record([
            record(home, day: "2026-10-06", down: 700, up: 70, at: now),
            record(office, day: "2026-10-06", down: 300, up: 30, at: now)
        ])

        let summaries = try store.fetchSummaries(
            referenceDate: now,
            calendar: context.calendar
        )
        #expect(summaries.count == 2)
        #expect(summaries.first { $0.identity == home }?.allTime.download == 700)
        #expect(summaries.first { $0.identity == office }?.allTime.download == 300)
    }

    @Test("Custom network names survive later samples and restart")
    func customNetworkNamePersistence() throws {
        let context = try TestContext()
        defer { context.cleanUp() }
        let url = context.directory.appendingPathComponent("usage.sqlite3")
        let identity = makeIdentity("Home-WiFi")
        let now = context.date(2026, 10, 6)

        do {
            let store = try TrafficStore(url: url)
            try store.record([
                record(identity, day: "2026-10-06", down: 10, up: 5, at: now)
            ])
            try store.setDisplayName("家里", for: identity.key)
            try store.touch(identity, at: now)
            #expect(
                try store.fetchSummaries(
                    referenceDate: now,
                    calendar: context.calendar
                ).first?.identity.displayName == "家里"
            )
        }

        let reopenedStore = try TrafficStore(url: url)
        #expect(
            try reopenedStore.fetchSummaries(
                referenceDate: now,
                calendar: context.calendar
            ).first?.identity.displayName == "家里"
        )
    }

    @Test("Restart persists totals but never persists a counter baseline")
    func restart() throws {
        let context = try TestContext()
        defer { context.cleanUp() }
        let url = context.directory.appendingPathComponent("usage.sqlite3")
        let identity = makeIdentity("Home-WiFi")
        let now = context.date(2026, 10, 6)
        do {
            let firstStore = try TrafficStore(url: url)
            try firstStore.record([
                record(identity, day: "2026-10-06", down: 42, up: 7, at: now)
            ])
        }

        let reopenedStore = try TrafficStore(url: url)
        let summary = try #require(
            reopenedStore.fetchSummaries(
                referenceDate: now,
                calendar: context.calendar
            ).first
        )
        #expect(summary.allTime == UsageAmount(download: 42, upload: 7))

        var freshEngine = AttributionEngine()
        let event = freshEngine.ingest(
            TrafficSample(
                identity: identity,
                counters: InterfaceCounters(received: 999_999, transmitted: 500_000),
                uptime: 1
            )
        )
        guard case .baseline = event else {
            Issue.record("A process restart must never reuse interface counters")
            return
        }
    }

    @Test("Clear history deletes network and daily rows")
    func clearHistory() throws {
        let context = try TestContext()
        defer { context.cleanUp() }
        let store = try context.makeStore()
        let identity = makeIdentity("Home-WiFi")
        let now = context.date(2026, 10, 6)
        try store.record([
            record(identity, day: "2026-10-06", down: 1, up: 2, at: now)
        ])
        try store.clearHistory()
        #expect(
            try store.fetchSummaries(
                referenceDate: now,
                calendar: context.calendar
            ).isEmpty
        )
    }

    @Test("Byte formatter uses binary units")
    func byteFormatter() {
        #expect(ByteCountText.string(0) == "0 B")
        #expect(ByteCountText.string(1_024) == "1.00 KB")
        #expect(ByteCountText.string(12_884_901_888) == "12.0 GB")
        #expect(ByteCountText.string(0, compact: true) == "0 B")
        #expect(ByteCountText.string(1_023, compact: true) == "1023 B")
        #expect(ByteCountText.string(3_198_157, compact: true) == "3.1 MB")
        #expect(ByteCountText.string(10_475_274, compact: true) == "10 MB")
        #expect(ByteCountText.string(10_485_760, compact: true) == "10 MB")
        #expect(ByteCountText.string(104_857_600, compact: true) == "100 MB")
    }

    private func makeIdentity(_ ssid: String) -> NetworkIdentity {
        NetworkIdentity(
            key: "wifi:\(ssid)",
            displayName: ssid,
            ssid: ssid,
            kind: .wifi,
            interfaceName: "en0"
        )
    }

    private func record(
        _ identity: NetworkIdentity,
        day: String,
        down: UInt64,
        up: UInt64,
        at date: Date
    ) -> UsageRecord {
        UsageRecord(
            identity: identity,
            day: day,
            amount: UsageAmount(download: down, upload: up),
            timestamp: date
        )
    }
}

private final class TestContext {
    let directory: URL
    let calendar: Calendar

    init() throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        self.calendar = calendar
    }

    func makeStore() throws -> TrafficStore {
        try TrafficStore(url: directory.appendingPathComponent("usage.sqlite3"))
    }

    func date(_ year: Int, _ month: Int, _ day: Int) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day))!
    }

    func cleanUp() {
        try? FileManager.default.removeItem(at: directory)
    }
}
