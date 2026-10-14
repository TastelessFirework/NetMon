import AppKit
import CoreLocation
import Foundation
import NetMonCore

struct DebugSnapshot {
    var currentSSID = "—"
    var interfaceName = "—"
    var receivedCounter: UInt64?
    var transmittedCounter: UInt64?
    var previousReceived: UInt64?
    var previousTransmitted: UInt64?
    var deltaDownload: UInt64 = 0
    var deltaUpload: UInt64 = 0
    var note = "等待第一次采样"
}

// Resolve app text and error descriptions at display time, including after a language change.
private enum AppNotice {
    case message(String)
    case error(Error)

    var text: String {
        switch self {
        case .message(let key): return L10n.text(key)
        case .error(let error): return error.localizedDescription
        }
    }
}

private struct PendingKey: Hashable {
    let identityKey: String
    let day: String
}

private struct PendingUsage {
    let identity: NetworkIdentity
    let day: String
    var amount: UsageAmount
    var timestamp: Date
}

@MainActor
final class AppModel {
    static let shared = AppModel()
    static let maximumCustomNetworkNameLength = 6

    private(set) var currentIdentity: NetworkIdentity?
    private(set) var currentInterface = "—"
    private var statusNotice: AppNotice?
    var statusMessage: String? { statusNotice?.text }
    private(set) var downloadSpeed = "0 B/s"
    private(set) var uploadSpeed = "0 B/s"
    private(set) var summaries: [NetworkSummary] = []
    private(set) var debug = DebugSnapshot()
    var trackWiFi: Bool
    var trackEthernet: Bool
    var launchAtLogin = false
    var debugLogging: Bool
    var locationStatus: String { locationAccess.statusText }
    var isLocationAuthorized: Bool { locationAccess.isAuthorized }
    private var settingsNotice: AppNotice?
    var settingsMessage: String? { settingsNotice?.text }

    private let store: TrafficStore
    private let resolver = NetworkResolver()
    private let counterReader = SystemCounterReader()
    private let locationAccess = LocationAccess()
    private let loginItemController = LoginItemController()
    private let debugLogger = DebugLogger()
    private let defaults = UserDefaults.standard
    private var attributor = AttributionEngine(maximumInterval: 15)
    private var timer: Timer?
    private var notificationTokens: [NSObjectProtocol] = []
    private var pending: [PendingKey: PendingUsage] = [:]
    private var knownIdentityKeys = Set<String>()
    private var lastObservedIdentity: NetworkIdentity?
    private var lastFlushUptime: TimeInterval = 0
    private var lastDayKey = DayKey.string(for: Date())
    private var started = false

    private lazy var networkChangeMonitor = NetworkChangeMonitor {
        [weak self] reason, pathHint in
        if let pathHint {
            self?.resolver.setUnderlyingPhysicalInterface(
                pathHint.physicalInterfaceName
            )
        }
        self?.handleBoundary(reason)
    }

    private init() {
        if defaults.object(forKey: "trackWiFi") == nil {
            defaults.set(true, forKey: "trackWiFi")
        }
        if defaults.object(forKey: "trackEthernet") == nil {
            defaults.set(true, forKey: "trackEthernet")
        }
        trackWiFi = defaults.bool(forKey: "trackWiFi")
        trackEthernet = defaults.bool(forKey: "trackEthernet")
        debugLogging = defaults.bool(forKey: "debugLogging")

        do {
            store = try TrafficStore()
        } catch {
            fatalError("Unable to initialize local database: \(error)")
        }

        locationAccess.onAuthorizationChange = { [weak self] in
            guard let self else { return }
            self.handleBoundary("location authorization changed")
        }
    }

    var currentSummary: NetworkSummary? {
        guard let key = currentIdentity?.key else { return nil }
        return summaries.first { $0.identity.key == key }
    }

    var currentNetworkDisplayName: String {
        currentSummary?.identity.localizedDisplayName
            ?? currentIdentity?.localizedDisplayName
            ?? L10n.text("未识别")
    }

    var currentCustomNetworkName: String? {
        currentSummary.flatMap { customNetworkName(for: $0.identity) }
    }

    var customizableNetworkSummaries: [NetworkSummary] {
        summaries.filter {
            $0.identity.kind.supportsCustomName
        }
    }

    func start() {
        guard !started else { return }
        started = true
        refreshSummaries()
        networkChangeMonitor.start()
        observePowerEvents()
        // Read the user's existing choice; new installs never register on launch.
        launchAtLogin = loginItemController.isEnabled

        sample()
        let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.sample() }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer

        if locationAccess.status == .notDetermined {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) { [weak self] in
                self?.locationAccess.request()
            }
        }
    }

    func stop() {
        guard started else { return }
        flushPending()
        timer?.invalidate()
        timer = nil
        networkChangeMonitor.stop()
        for token in notificationTokens {
            NSWorkspace.shared.notificationCenter.removeObserver(token)
        }
        notificationTokens.removeAll()
        started = false
    }

    func setTrackWiFi(_ enabled: Bool) {
        trackWiFi = enabled
        defaults.set(enabled, forKey: "trackWiFi")
        handleBoundary("Wi-Fi tracking setting changed")
    }

    func setTrackEthernet(_ enabled: Bool) {
        trackEthernet = enabled
        defaults.set(enabled, forKey: "trackEthernet")
        handleBoundary("Ethernet tracking setting changed")
    }

    func setDebugLogging(_ enabled: Bool) {
        debugLogging = enabled
        debugLogger.isEnabled = enabled
        debugLogger.log("Debug logging \(enabled ? "enabled" : "disabled")")
    }

    func setLaunchAtLogin(_ enabled: Bool) {
        do {
            try loginItemController.setEnabled(enabled)
            settingsNotice = nil
        } catch {
            settingsNotice = .error(error)
        }
        launchAtLogin = loginItemController.isEnabled
    }

    func defaultNetworkName(for identity: NetworkIdentity) -> String {
        identity.ssid ?? identity.kind.displayName
    }

    func customNetworkName(for identity: NetworkIdentity) -> String? {
        let defaultName = defaultNetworkName(for: identity)
        return identity.displayName == defaultName ? nil : identity.displayName
    }

    func setNetworkName(_ value: String, for identityKey: String) {
        guard let summary = summaries.first(where: {
            $0.identity.key == identityKey
        }), summary.identity.kind.supportsCustomName else {
            settingsNotice = .message("所选 Wi-Fi、Ethernet 或 PPP 尚不可命名。")
            return
        }

        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        let customName = String(
            trimmed.prefix(Self.maximumCustomNetworkNameLength)
        )
        let displayName = customName.isEmpty
            ? defaultNetworkName(for: summary.identity)
            : customName

        do {
            try store.setDisplayName(displayName, for: identityKey)
            refreshSummaries()
            settingsNotice = .message(
                customName.isEmpty
                    ? "已恢复当前网络的默认名称。"
                    : "当前网络名称已保存。"
            )
        } catch {
            settingsNotice = .error(error)
        }
    }

    func requestLocationAccess() {
        locationAccess.request()
    }

    func revealDatabase() {
        NSWorkspace.shared.activateFileViewerSelecting([store.url])
    }

    func revealDebugLog() {
        let url = debugLogger.fileURL
        if FileManager.default.fileExists(atPath: url.path) {
            NSWorkspace.shared.activateFileViewerSelecting([url])
        } else {
            settingsNotice = .message("启用调试日志并等待一次采样后才会创建日志文件。")
        }
    }

    func clearHistory() {
        pending.removeAll()
        attributor.invalidate(reason: "history cleared")
        do {
            try store.clearHistory()
            summaries = []
            knownIdentityKeys = []
            settingsNotice = .message("历史数据已清除。")
            sample()
        } catch {
            settingsNotice = .error(error)
        }
    }

    private func sample() {
        let now = Date()
        let uptime = ProcessInfo.processInfo.systemUptime
        let day = DayKey.string(for: now)
        if day != lastDayKey {
            flushPending()
            lastDayKey = day
            refreshSummaries()
        }

        let resolution = resolver.resolve()
        currentInterface = resolution.interfaceName ?? "—"
        statusNotice = resolution.issue.map(AppNotice.message)

        if lastObservedIdentity?.key != resolution.identity?.key {
            let oldName = lastObservedIdentity?.displayName ?? "Disconnected"
            let newName = resolution.identity?.displayName ?? "Disconnected"
            debugLogger.log("Network changed: \(oldName) -> \(newName)")
            lastObservedIdentity = resolution.identity
        }
        currentIdentity = resolution.identity

        guard let identity = resolution.identity else {
            let previous = attributor.baseline
            _ = attributor.ingest(nil)
            updateDebug(
                identity: nil,
                counters: nil,
                previous: previous,
                delta: .init(),
                note: resolution.issue ?? "network unavailable"
            )
            updateSpeeds(download: "0 B/s", upload: "0 B/s")
            return
        }

        guard shouldTrack(identity) else {
            let previous = attributor.baseline
            _ = attributor.ingest(nil)
            statusNotice = .message("已在设置中暂停此网络类型的统计")
            updateDebug(
                identity: identity,
                counters: nil,
                previous: previous,
                delta: .init(),
                note: "tracking disabled"
            )
            updateSpeeds(download: "0 B/s", upload: "0 B/s")
            return
        }

        do {
            if !knownIdentityKeys.contains(identity.key) {
                try store.touch(identity, at: now)
                knownIdentityKeys.insert(identity.key)
                refreshSummaries()
            }

            let counters = try counterReader.read(
                interfaceName: identity.interfaceName
            )
            let previous = attributor.baseline
            let event = attributor.ingest(
                TrafficSample(identity: identity, counters: counters, uptime: uptime)
            )

            switch event {
            case .baseline:
                updateDebug(
                    identity: identity,
                    counters: counters,
                    previous: previous,
                    delta: .init(),
                    note: "baseline established"
                )
                updateSpeeds(download: "0 B/s", upload: "0 B/s")

            case .reset(let reason, _):
                updateDebug(
                    identity: identity,
                    counters: counters,
                    previous: previous,
                    delta: .init(),
                    note: reason
                )
                debugLogger.log("Baseline reset: \(reason)")
                updateSpeeds(download: "0 B/s", upload: "0 B/s")

            case .delta(_, let amount, let interval):
                accumulate(identity: identity, amount: amount, date: now)
                applyToSummary(identity: identity, amount: amount, date: now)
                let downloadSpeed = ByteCountText.speed(
                    bytes: amount.download,
                    interval: interval
                )
                let uploadSpeed = ByteCountText.speed(
                    bytes: amount.upload,
                    interval: interval
                )
                updateSpeeds(download: downloadSpeed, upload: uploadSpeed)
                updateDebug(
                    identity: identity,
                    counters: counters,
                    previous: previous,
                    delta: amount,
                    note: "stable interval"
                )
                if debugLogging {
                    debugLogger.log(
                        "SSID=\(identity.ssid ?? identity.displayName) " +
                        "Interface=\(identity.interfaceName) " +
                        "RX delta=\(amount.download) TX delta=\(amount.upload)"
                    )
                }
            }

            if uptime - lastFlushUptime >= 10 {
                flushPending()
                lastFlushUptime = uptime
            }
        } catch {
            statusNotice = .error(error)
            let previous = attributor.baseline
            _ = attributor.ingest(nil)
            updateSpeeds(download: "0 B/s", upload: "0 B/s")
            updateDebug(
                identity: identity,
                counters: nil,
                previous: previous,
                delta: .init(),
                note: error.localizedDescription
            )
        }
    }

    private func shouldTrack(_ identity: NetworkIdentity) -> Bool {
        switch identity.kind {
        case .wifi: return trackWiFi
        case .ethernet: return trackEthernet
        case .ppp, .vpn, .other: return true
        }
    }

    private func accumulate(
        identity: NetworkIdentity,
        amount: UsageAmount,
        date: Date
    ) {
        guard amount.download > 0 || amount.upload > 0 else { return }
        let day = DayKey.string(for: date)
        let key = PendingKey(identityKey: identity.key, day: day)
        if var item = pending[key] {
            item.amount.download = saturatedAdd(item.amount.download, amount.download)
            item.amount.upload = saturatedAdd(item.amount.upload, amount.upload)
            item.timestamp = date
            pending[key] = item
        } else {
            pending[key] = PendingUsage(
                identity: identity,
                day: day,
                amount: amount,
                timestamp: date
            )
        }
    }

    private func applyToSummary(
        identity: NetworkIdentity,
        amount: UsageAmount,
        date: Date
    ) {
        var values = summaries
        guard let index = values.firstIndex(where: {
            $0.identity.key == identity.key
        }) else { return }

        values[index].today.download = saturatedAdd(
            values[index].today.download,
            amount.download
        )
        values[index].today.upload = saturatedAdd(
            values[index].today.upload,
            amount.upload
        )
        values[index].recentSevenDays.download = saturatedAdd(
            values[index].recentSevenDays.download,
            amount.download
        )
        values[index].recentSevenDays.upload = saturatedAdd(
            values[index].recentSevenDays.upload,
            amount.upload
        )
        values[index].month.download = saturatedAdd(
            values[index].month.download,
            amount.download
        )
        values[index].month.upload = saturatedAdd(
            values[index].month.upload,
            amount.upload
        )
        values[index].allTime.download = saturatedAdd(
            values[index].allTime.download,
            amount.download
        )
        values[index].allTime.upload = saturatedAdd(
            values[index].allTime.upload,
            amount.upload
        )
        values[index].lastUsed = date
        summaries = values
    }

    private func flushPending() {
        guard !pending.isEmpty else { return }
        let records = pending.values.map {
            UsageRecord(
                identity: $0.identity,
                day: $0.day,
                amount: $0.amount,
                timestamp: $0.timestamp
            )
        }
        do {
            try store.record(records)
            pending.removeAll()
            refreshSummaries()
        } catch {
            statusNotice = .error(error)
            debugLogger.log("Database flush failed: \(error.localizedDescription)")
        }
    }

    private func refreshSummaries() {
        do {
            summaries = try store.fetchSummaries()
            knownIdentityKeys = Set(summaries.map { $0.identity.key })
        } catch {
            statusNotice = .error(error)
        }
    }

    private func handleBoundary(_ reason: String) {
        flushPending()
        attributor.invalidate(reason: reason)
        updateSpeeds(download: "0 B/s", upload: "0 B/s")
        debug.note = reason
        debugLogger.log("Boundary: \(reason); baseline invalidated")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
            self?.sample()
        }
    }

    private func observePowerEvents() {
        let center = NSWorkspace.shared.notificationCenter
        notificationTokens.append(
            center.addObserver(
                forName: NSWorkspace.willSleepNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor in
                    self?.flushPending()
                    self?.attributor.invalidate(reason: "Mac will sleep")
                    self?.debugLogger.log("Mac will sleep; baseline invalidated")
                }
            }
        )
        notificationTokens.append(
            center.addObserver(
                forName: NSWorkspace.didWakeNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor in
                    self?.handleBoundary("Mac woke from sleep")
                }
            }
        )
    }

    private func updateSpeeds(download: String, upload: String) {
        if downloadSpeed != download {
            downloadSpeed = download
        }
        if uploadSpeed != upload {
            uploadSpeed = upload
        }
    }

    private func updateDebug(
        identity: NetworkIdentity?,
        counters: InterfaceCounters?,
        previous: TrafficSample?,
        delta: UsageAmount,
        note: String
    ) {
        debug = DebugSnapshot(
            currentSSID: identity?.ssid ?? identity?.displayName ?? "—",
            interfaceName: identity?.interfaceName ?? currentInterface,
            receivedCounter: counters?.received,
            transmittedCounter: counters?.transmitted,
            previousReceived: previous?.counters.received,
            previousTransmitted: previous?.counters.transmitted,
            deltaDownload: delta.download,
            deltaUpload: delta.upload,
            note: note
        )
    }

    private func saturatedAdd(_ lhs: UInt64, _ rhs: UInt64) -> UInt64 {
        let result = lhs.addingReportingOverflow(rhs)
        return result.overflow ? UInt64.max : result.partialValue
    }
}
