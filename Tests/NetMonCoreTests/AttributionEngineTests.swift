import Foundation
import Testing
@testable import NetMonCore

@Suite("Traffic attribution boundaries")
struct AttributionEngineTests {
    private let home = NetworkIdentity(
        key: "wifi:Home-WiFi",
        displayName: "Home-WiFi",
        ssid: "Home-WiFi",
        kind: .wifi,
        interfaceName: "en0"
    )
    private let office = NetworkIdentity(
        key: "wifi:Office-WiFi",
        displayName: "Office-WiFi",
        ssid: "Office-WiFi",
        kind: .wifi,
        interfaceName: "en0"
    )
    private let ethernet = NetworkIdentity(
        key: "ethernet:en5:Ethernet",
        displayName: "Ethernet",
        ssid: nil,
        kind: .ethernet,
        interfaceName: "en5"
    )

    @Test("Stable network produces separate RX and TX deltas")
    func stableNetworkDelta() {
        var engine = AttributionEngine()
        _ = engine.ingest(sample(home, rx: 1_000, tx: 500, at: 10))
        let event = engine.ingest(sample(home, rx: 1_400, tx: 620, at: 11))

        guard case .delta(let identity, let amount, let interval) = event else {
            Issue.record("Expected a delta")
            return
        }
        #expect(identity == home)
        #expect(amount == UsageAmount(download: 400, upload: 120))
        #expect(interval == 1)
    }

    @Test("Wi-Fi A to B discards the boundary interval")
    func wifiAToB() {
        var engine = AttributionEngine()
        _ = engine.ingest(sample(home, rx: 1_000, tx: 500, at: 10))
        let boundary = engine.ingest(sample(office, rx: 1_900, tx: 800, at: 11))
        guard case .reset(let reason, _) = boundary else {
            Issue.record("Expected boundary reset")
            return
        }
        #expect(reason.contains("changed"))

        let event = engine.ingest(sample(office, rx: 2_200, tx: 900, at: 12))
        guard case .delta(_, let amount, _) = event else {
            Issue.record("Expected office delta")
            return
        }
        #expect(amount == UsageAmount(download: 300, upload: 100))
    }

    @Test("Wi-Fi B to A starts a fresh A baseline")
    func wifiBToA() {
        var engine = AttributionEngine()
        _ = engine.ingest(sample(office, rx: 2_000, tx: 1_000, at: 20))
        _ = engine.ingest(sample(home, rx: 2_400, tx: 1_200, at: 21))
        let event = engine.ingest(sample(home, rx: 2_550, tx: 1_260, at: 22))

        guard case .delta(_, let amount, _) = event else {
            Issue.record("Expected home delta")
            return
        }
        #expect(amount == UsageAmount(download: 150, upload: 60))
    }

    @Test("SSID event protects a fast A-B-A switch between samples")
    func eventInvalidationProtectsFastSwitch() {
        var engine = AttributionEngine()
        _ = engine.ingest(sample(home, rx: 1_000, tx: 500, at: 10))
        _ = engine.invalidate(reason: "SSID event")
        let event = engine.ingest(sample(home, rx: 5_000, tx: 2_000, at: 11))

        guard case .baseline = event else {
            Issue.record("Traffic across a hidden switch must not be attributed")
            return
        }
    }

    @Test("Wi-Fi to Ethernet discards the boundary interval")
    func wifiToEthernet() {
        var engine = AttributionEngine()
        _ = engine.ingest(sample(home, rx: 100, tx: 100, at: 1))
        let event = engine.ingest(sample(ethernet, rx: 9_000, tx: 7_000, at: 2))
        guard case .reset = event else {
            Issue.record("Expected interface boundary reset")
            return
        }
    }

    @Test("Disconnect and reconnect establishes a new baseline")
    func disconnect() {
        var engine = AttributionEngine()
        _ = engine.ingest(sample(home, rx: 100, tx: 100, at: 1))
        _ = engine.ingest(nil)
        let event = engine.ingest(sample(home, rx: 5_000, tx: 4_000, at: 3))
        guard case .baseline = event else {
            Issue.record("Reconnect must establish a new baseline")
            return
        }
    }

    @Test("Wake invalidation prevents a huge sleep delta")
    func wakeInvalidation() {
        var engine = AttributionEngine()
        _ = engine.ingest(sample(home, rx: 100, tx: 100, at: 1))
        _ = engine.invalidate(reason: "wake")
        let event = engine.ingest(sample(home, rx: 50_000, tx: 40_000, at: 100))
        guard case .baseline = event else {
            Issue.record("Wake must establish a new baseline")
            return
        }
    }

    @Test("Counter reset never produces a negative or huge delta")
    func counterReset() {
        var engine = AttributionEngine()
        _ = engine.ingest(sample(home, rx: 10_000, tx: 8_000, at: 1))
        let event = engine.ingest(sample(home, rx: 200, tx: 100, at: 2))
        guard case .reset(let reason, _) = event else {
            Issue.record("Expected reset")
            return
        }
        #expect(reason.contains("counter"))
    }

    @Test("Long sampling gap is treated as a suspension")
    func longGap() {
        var engine = AttributionEngine(maximumInterval: 15)
        _ = engine.ingest(sample(home, rx: 100, tx: 100, at: 1))
        let event = engine.ingest(sample(home, rx: 50_000, tx: 40_000, at: 30))
        guard case .reset(let reason, _) = event else {
            Issue.record("Expected sampling gap reset")
            return
        }
        #expect(reason.contains("gap"))
    }

    private func sample(
        _ identity: NetworkIdentity,
        rx: UInt64,
        tx: UInt64,
        at uptime: TimeInterval
    ) -> TrafficSample {
        TrafficSample(
            identity: identity,
            counters: InterfaceCounters(received: rx, transmitted: tx),
            uptime: uptime
        )
    }
}
