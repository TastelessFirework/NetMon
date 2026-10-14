import Foundation

public struct TrafficSample: Equatable, Sendable {
    public let identity: NetworkIdentity
    public let counters: InterfaceCounters
    public let uptime: TimeInterval

    public init(
        identity: NetworkIdentity,
        counters: InterfaceCounters,
        uptime: TimeInterval
    ) {
        self.identity = identity
        self.counters = counters
        self.uptime = uptime
    }
}

public enum AttributionEvent: Equatable, Sendable {
    case baseline(TrafficSample)
    case delta(
        identity: NetworkIdentity,
        amount: UsageAmount,
        interval: TimeInterval
    )
    case reset(reason: String, newBaseline: TrafficSample?)
}

/// Attributes a counter difference only when both ends of the interval refer to
/// the exact same logical network and BSD interface.
public struct AttributionEngine: Sendable {
    public private(set) var baseline: TrafficSample?
    public let maximumInterval: TimeInterval

    public init(maximumInterval: TimeInterval = 15) {
        self.maximumInterval = maximumInterval
    }

    @discardableResult
    public mutating func ingest(_ sample: TrafficSample?) -> AttributionEvent {
        guard let sample else {
            baseline = nil
            return .reset(reason: "network unavailable", newBaseline: nil)
        }

        guard let previous = baseline else {
            baseline = sample
            return .baseline(sample)
        }

        guard previous.identity.key == sample.identity.key,
              previous.identity.interfaceName == sample.identity.interfaceName else {
            baseline = sample
            return .reset(reason: "network or interface changed", newBaseline: sample)
        }

        let interval = sample.uptime - previous.uptime
        guard interval > 0, interval <= maximumInterval else {
            baseline = sample
            return .reset(reason: "sampling gap", newBaseline: sample)
        }

        guard sample.counters.received >= previous.counters.received,
              sample.counters.transmitted >= previous.counters.transmitted else {
            baseline = sample
            return .reset(reason: "interface counter reset", newBaseline: sample)
        }

        let amount = UsageAmount(
            download: sample.counters.received - previous.counters.received,
            upload: sample.counters.transmitted - previous.counters.transmitted
        )
        baseline = sample
        return .delta(identity: sample.identity, amount: amount, interval: interval)
    }

    @discardableResult
    public mutating func invalidate(reason: String) -> AttributionEvent {
        baseline = nil
        return .reset(reason: reason, newBaseline: nil)
    }
}
