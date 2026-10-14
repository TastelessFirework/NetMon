import AppKit
import NetMonCore

private struct UsageMenuItems {
    let total: NSMenuItem
    let upload: NSMenuItem
    let download: NSMenuItem
}

private struct NetworkMenuItems {
    let root: NSMenuItem
    let today: UsageMenuItems
    let recentSevenDays: UsageMenuItems
    let month: UsageMenuItems
    let allTime: UsageMenuItems
    let typeAndInterface: NSMenuItem
    let firstSeen: NSMenuItem
}

private struct AllNetworksMenuItems {
    let root: NSMenuItem
    let today: UsageMenuItems
    let recentSevenDays: UsageMenuItems
    let month: UsageMenuItems
    let allTime: UsageMenuItems
}

@MainActor
final class StatusMenuController: NSObject, NSMenuDelegate {
    private static let widthAnchor = String(repeating: "\u{2007}", count: 16)

    private let model: AppModel
    private let rootMenu = NSMenu()
    private let currentNetworkMenu = NSMenu()
    private let networksMenu = NSMenu()
    private let settingsMenu = NSMenu()
    private let networkNamesMenu = NSMenu()
    private let debugMenu = NSMenu()
    private let statusBarPresentation = StatusBarPresentation()
    private let networkServiceOrderManager = NetworkServiceOrderManager()

    private var statusItem: NSStatusItem?
    private var refreshTimer: Timer?
    private var isRootMenuOpen = false
    private var networkOrder: [String] = []
    private var networkItems: [String: NetworkMenuItems] = [:]
    private var allNetworksItems: AllNetworksMenuItems!
    private let allNetworksSeparator = NSMenuItem.separator()
    private var networkNameMenuSignature: [String] = []
    private var networkServiceItems: [String: NSMenuItem] = [:]

    private var networkSettingsItem: NSMenuItem!
    private var networkSettingsSeparator: NSMenuItem!
    private var networkServiceMessageItem: NSMenuItem!
    private var currentNameItem: NSMenuItem!
    private var currentInterfaceItem: NSMenuItem!
    private var statusMessageItem: NSMenuItem!
    private var todayItems: UsageMenuItems!
    private var uploadSpeedItem: NSMenuItem!
    private var downloadSpeedItem: NSMenuItem!
    private var monthItems: UsageMenuItems!

    private var languageItems: [AppLanguage: NSMenuItem] = [:]
    private var needsLanguageRebuild = false

    private var launchAtLoginItem: NSMenuItem!
    private var trackWiFiItem: NSMenuItem!
    private var trackEthernetItem: NSMenuItem!
    private var locationStatusItem: NSMenuItem!
    private var requestLocationItem: NSMenuItem!
    private var settingsMessageSeparator: NSMenuItem!
    private var settingsMessageItem: NSMenuItem!

    private var debugSSIDItem: NSMenuItem!
    private var debugInterfaceItem: NSMenuItem!
    private var debugTXItem: NSMenuItem!
    private var debugRXItem: NSMenuItem!
    private var debugPreviousTXItem: NSMenuItem!
    private var debugPreviousRXItem: NSMenuItem!
    private var debugDeltaTXItem: NSMenuItem!
    private var debugDeltaRXItem: NSMenuItem!
    private var debugStateItem: NSMenuItem!
    private var debugLoggingItem: NSMenuItem!

    init(model: AppModel) {
        self.model = model
        super.init()
    }

    func start() {
        guard statusItem == nil else { return }

        configure(menu: rootMenu)
        configure(menu: currentNetworkMenu)
        configure(menu: networksMenu)
        configure(menu: settingsMenu)
        configure(menu: networkNamesMenu)
        configure(menu: debugMenu)
        rootMenu.delegate = self
        currentNetworkMenu.delegate = self

        buildRootMenu()
        buildCurrentNetworkMenu()
        buildSettingsMenu()
        buildDebugMenu()
        buildAllNetworksSummaryMenu()
        rebuildNetworksMenu(model.summaries)

        let statusItem = NSStatusBar.system.statusItem(withLength: 0)
        statusBarPresentation.configure(statusItem: statusItem)
        statusItem.menu = rootMenu
        self.statusItem = statusItem

        refreshMenu(allowStructureChanges: true)

        let timer = Timer(timeInterval: 0.5, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.refreshMenu(
                    allowStructureChanges: self?.isRootMenuOpen == false
                )
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        refreshTimer = timer
    }

    func stop() {
        refreshTimer?.invalidate()
        refreshTimer = nil
        if let statusItem {
            NSStatusBar.system.removeStatusItem(statusItem)
        }
        statusItem = nil
    }

    func menuWillOpen(_ menu: NSMenu) {
        if menu === currentNetworkMenu {
            refreshCurrentNetworkMenu()
            return
        }
        guard menu === rootMenu else { return }
        refreshMenu(allowStructureChanges: true)
        isRootMenuOpen = true
    }

    func menuDidClose(_ menu: NSMenu) {
        guard menu === rootMenu else { return }
        isRootMenuOpen = false
        rebuildForLanguageIfNeeded()
        refreshMenu(allowStructureChanges: true)
    }

    private func configure(menu: NSMenu) {
        menu.autoenablesItems = false
    }

    private func buildRootMenu() {
        rootMenu.removeAllItems()

        let currentNetworkItem = emphasizedSubmenuItem(
            L10n.text("当前网络") + Self.widthAnchor,
            submenu: currentNetworkMenu,
            accessibilityTitle: L10n.text("当前网络")
        )
        currentNetworkItem.setAccessibilityHelp(L10n.text("展开 macOS 网络服务顺序"))
        rootMenu.addItem(currentNetworkItem)
        currentNameItem = readOnlyItem(L10n.text("未识别"))
        currentInterfaceItem = readOnlyItem("— · —")
        statusMessageItem = readOnlyItem(
            "",
            systemImage: "exclamationmark.triangle"
        )
        statusMessageItem.isHidden = true
        rootMenu.addItem(currentNameItem)
        rootMenu.addItem(currentInterfaceItem)
        rootMenu.addItem(statusMessageItem)
        rootMenu.addItem(.separator())

        uploadSpeedItem = readOnlyItem(L10n.text("当前上传速度  0 B/s"), systemImage: "arrow.up")
        downloadSpeedItem = readOnlyItem(
            L10n.text("当前下载速度  0 B/s"),
            systemImage: "arrow.down"
        )
        rootMenu.addItem(uploadSpeedItem)
        rootMenu.addItem(downloadSpeedItem)
        rootMenu.addItem(.separator())

        rootMenu.addItem(readOnlyItem(L10n.text("今日"), emphasized: true))
        todayItems = addUsageItems(to: rootMenu)
        rootMenu.addItem(.separator())

        rootMenu.addItem(readOnlyItem(L10n.text("本月"), emphasized: true))
        monthItems = addUsageItems(to: rootMenu)
        rootMenu.addItem(.separator())

        rootMenu.addItem(
            submenuItem(L10n.text("所有网络"), systemImage: "network", submenu: networksMenu)
        )
        rootMenu.addItem(
            submenuItem(L10n.text("设置"), systemImage: "gearshape", submenu: settingsMenu)
        )
        rootMenu.addItem(
            submenuItem("Debug", systemImage: "ladybug", submenu: debugMenu)
        )

        rootMenu.addItem(.separator())
        rootMenu.addItem(actionItem(L10n.text("退出 NetMon"), action: #selector(quitApplication)))
    }

    private func buildCurrentNetworkMenu() {
        networkSettingsItem = actionItem(
            L10n.text("网络设置…"),
            action: #selector(openNetworkSettings)
        )
        networkSettingsItem.image = symbol(
            "network",
            description: L10n.text("网络设置")
        )
        networkSettingsSeparator = .separator()
        networkServiceMessageItem = readOnlyItem(
            L10n.text("正在读取网络服务顺序…"),
            systemImage: "clock"
        )
        rebuildCurrentNetworkMenu(with: nil)
        refreshCurrentNetworkMenu()
    }

    private func refreshCurrentNetworkMenu() {
        do {
            let snapshot = try networkServiceOrderManager.read()
            rebuildCurrentNetworkMenu(with: snapshot)
        } catch {
            showNetworkServiceReadFailure(error)
        }
    }

    private func rebuildCurrentNetworkMenu(
        with snapshot: SystemNetworkServiceOrderSnapshot?
    ) {
        currentNetworkMenu.removeAllItems()
        currentNetworkMenu.addItem(networkSettingsItem)
        currentNetworkMenu.addItem(networkSettingsSeparator)

        guard let snapshot else {
            currentNetworkMenu.addItem(networkServiceMessageItem)
            return
        }

        guard !snapshot.services.isEmpty else {
            setTitle(L10n.text("当前没有可排序的网络服务"), on: networkServiceMessageItem)
            networkServiceMessageItem.image = symbol(
                "exclamationmark.triangle",
                description: networkServiceMessageItem.title
            )
            currentNetworkMenu.addItem(networkServiceMessageItem)
            return
        }

        let validIDs = Set(snapshot.services.map(\.id))
        networkServiceItems = networkServiceItems.filter {
            validIDs.contains($0.key)
        }
        for service in snapshot.services {
            let item: NSMenuItem
            if let existing = networkServiceItems[service.id] {
                item = existing
            } else {
                item = actionItem(
                    service.name,
                    action: #selector(makeNetworkServicePreferred(_:))
                )
                item.representedObject = service.id
                networkServiceItems[service.id] = item
            }
            setTitle(service.name, on: item)
            item.state = service.id == snapshot.preferredServiceID ? .on : .off
            item.setAccessibilityHelp(
                service.isEnabled
                    ? L10n.text("将此服务移到 macOS 网络服务顺序第一位")
                    : L10n.text("此系统网络服务当前已停用；仍可调整其服务顺序")
            )
            currentNetworkMenu.addItem(item)
        }
    }

    private func showNetworkServiceReadFailure(_ error: Error) {
        setTitle(L10n.text("无法读取网络服务顺序"), on: networkServiceMessageItem)
        networkServiceMessageItem.image = symbol(
            "exclamationmark.triangle",
            description: networkServiceMessageItem.title
        )
        networkServiceMessageItem.toolTip = error.localizedDescription
        rebuildCurrentNetworkMenu(with: nil)
    }

    private func buildSettingsMenu() {
        settingsMenu.removeAllItems()
        languageItems.removeAll()
        for language in AppLanguage.allCases {
            let item = actionItem(
                language == .chinese ? "中文" : "English",
                action: #selector(selectLanguage(_:))
            )
            item.representedObject = language.rawValue
            item.state = L10n.language == language ? .on : .off
            languageItems[language] = item
            settingsMenu.addItem(item)
        }
        settingsMenu.addItem(.separator())

        launchAtLoginItem = actionItem(
            L10n.text("启动时自动运行"),
            action: #selector(toggleLaunchAtLogin)
        )
        trackWiFiItem = actionItem(
            L10n.text("统计 Wi-Fi"),
            action: #selector(toggleTrackWiFi)
        )
        trackEthernetItem = actionItem(
            L10n.text("统计 Ethernet"),
            action: #selector(toggleTrackEthernet)
        )
        settingsMenu.addItem(launchAtLoginItem)
        settingsMenu.addItem(trackWiFiItem)
        settingsMenu.addItem(trackEthernetItem)

        settingsMenu.addItem(.separator())
        settingsMenu.addItem(
            submenuItem(
                L10n.text("自定义网络名称"),
                systemImage: "pencil",
                submenu: networkNamesMenu
            )
        )
        rebuildNetworkNamesMenu(model.customizableNetworkSummaries)

        settingsMenu.addItem(.separator())
        locationStatusItem = readOnlyItem(L10n.text("SSID 位置权限：尚未请求"))
        requestLocationItem = actionItem(
            L10n.text("允许读取 SSID…"),
            action: #selector(requestLocationAccess)
        )
        settingsMenu.addItem(locationStatusItem)
        settingsMenu.addItem(requestLocationItem)

        settingsMenu.addItem(.separator())
        settingsMenu.addItem(
            actionItem(
                L10n.text("在 Finder 中显示数据库"),
                action: #selector(revealDatabase)
            )
        )

        let clearMenu = NSMenu()
        configure(menu: clearMenu)
        clearMenu.addItem(readOnlyItem(L10n.text("此操作无法撤销")))
        clearMenu.addItem(
            actionItem(L10n.text("确认清除"), action: #selector(clearHistory))
        )
        settingsMenu.addItem(
            submenuItem(L10n.text("清除历史数据…"), systemImage: "trash", submenu: clearMenu)
        )

        settingsMessageSeparator = .separator()
        settingsMessageItem = readOnlyItem("")
        settingsMessageSeparator.isHidden = true
        settingsMessageItem.isHidden = true
        settingsMenu.addItem(settingsMessageSeparator)
        settingsMenu.addItem(settingsMessageItem)
    }

    private func buildDebugMenu() {
        debugMenu.removeAllItems()

        debugSSIDItem = readOnlyItem("Current SSID: —")
        debugInterfaceItem = readOnlyItem("Interface: —")
        debugTXItem = readOnlyItem("TX counter: —")
        debugRXItem = readOnlyItem("RX counter: —")
        debugPreviousTXItem = readOnlyItem("Previous TX: —")
        debugPreviousRXItem = readOnlyItem("Previous RX: —")
        debugDeltaTXItem = readOnlyItem("Delta TX: 0")
        debugDeltaRXItem = readOnlyItem("Delta RX: 0")
        debugStateItem = readOnlyItem(L10n.text("State: 等待第一次采样"))

        for item in [
            debugSSIDItem!,
            debugInterfaceItem!,
            debugTXItem!,
            debugRXItem!,
            debugPreviousTXItem!,
            debugPreviousRXItem!,
            debugDeltaTXItem!,
            debugDeltaRXItem!,
            debugStateItem!,
        ] {
            debugMenu.addItem(item)
        }

        debugMenu.addItem(.separator())
        debugLoggingItem = actionItem(
            L10n.text("写入调试日志"),
            action: #selector(toggleDebugLogging)
        )
        debugMenu.addItem(debugLoggingItem)
        debugMenu.addItem(
            actionItem(
                L10n.text("在 Finder 中显示调试日志"),
                action: #selector(revealDebugLog)
            )
        )
    }

    private func addUsageItems(to menu: NSMenu) -> UsageMenuItems {
        let items = UsageMenuItems(
            total: readOnlyItem(L10n.text("总流量  0 B"), systemImage: "sum"),
            upload: readOnlyItem(L10n.text("上传  0 B"), systemImage: "arrow.up"),
            download: readOnlyItem(L10n.text("下载  0 B"), systemImage: "arrow.down")
        )
        menu.addItem(items.total)
        menu.addItem(items.upload)
        menu.addItem(items.download)
        return items
    }

    private func refreshMenu(allowStructureChanges: Bool) {
        if allowStructureChanges { rebuildForLanguageIfNeeded() }
        setTitle(
            model.currentNetworkDisplayName,
            on: currentNameItem
        )
        setTitle(
            "\(model.currentIdentity?.kind.localizedDisplayName ?? "—") · " +
                model.currentInterface,
            on: currentInterfaceItem
        )

        if let message = model.statusMessage {
            setTitle(L10n.text(message), on: statusMessageItem)
            if allowStructureChanges {
                statusMessageItem.isHidden = false
            }
        } else if allowStructureChanges {
            statusMessageItem.isHidden = true
        }

        updateUsage(model.currentSummary?.today ?? .init(), items: todayItems)
        updateUsage(model.currentSummary?.month ?? .init(), items: monthItems)
        setTitle(L10n.format("当前上传速度  {0}", model.uploadSpeed), on: uploadSpeedItem)
        setTitle(L10n.format("当前下载速度  {0}", model.downloadSpeed), on: downloadSpeedItem)
        statusBarPresentation.update(
            statusItem: statusItem,
            uploadSpeed: model.uploadSpeed,
            downloadSpeed: model.downloadSpeed,
            networkNameLabel: model.currentCustomNetworkName ?? "usage",
            currentNetworkName: model.currentNetworkDisplayName,
            todayTotal: ByteCountText.string(
                model.currentSummary?.today.total ?? 0,
                compact: true
            )
        )

        refreshNetworks(allowStructureChanges: allowStructureChanges)
        refreshSettings(allowStructureChanges: allowStructureChanges)
        refreshDebug()
    }

    private func updateUsage(_ amount: UsageAmount, items: UsageMenuItems) {
        setTitle(L10n.format("总流量  {0}", ByteCountText.string(amount.total)), on: items.total)
        setTitle(L10n.format("上传  {0}", ByteCountText.string(amount.upload)), on: items.upload)
        setTitle(
            L10n.format("下载  {0}", ByteCountText.string(amount.download)),
            on: items.download
        )
    }

    private func refreshNetworks(allowStructureChanges: Bool) {
        let summaries = model.summaries
        let order = summaries.map(\.identity.key)
        if order != networkOrder, allowStructureChanges {
            rebuildNetworksMenu(summaries)
        }

        let totals = NetworkUsageTotals(summaries: summaries)
        setTitle(
            L10n.text("所有网络  ") + ByteCountText.string(totals.allTime.total),
            on: allNetworksItems.root
        )
        updateUsage(totals.today, items: allNetworksItems.today)
        updateUsage(totals.recentSevenDays, items: allNetworksItems.recentSevenDays)
        updateUsage(totals.month, items: allNetworksItems.month)
        updateUsage(totals.allTime, items: allNetworksItems.allTime)

        for summary in summaries {
            guard let items = networkItems[summary.identity.key] else { continue }
            setTitle(
                "\(summary.identity.localizedDisplayName)  " +
                    ByteCountText.string(summary.allTime.total),
                on: items.root
            )
            updateUsage(summary.today, items: items.today)
            updateUsage(summary.recentSevenDays, items: items.recentSevenDays)
            updateUsage(summary.month, items: items.month)
            updateUsage(summary.allTime, items: items.allTime)
            setTitle(
                "\(summary.identity.kind.localizedDisplayName) · " +
                    summary.identity.interfaceName,
                on: items.typeAndInterface
            )
            setTitle(
                L10n.text("首次发现 ") + summary.firstSeen.formatted(
                    Date.FormatStyle(date: .abbreviated, time: .shortened)
                        .locale(L10n.language.locale)
                ),
                on: items.firstSeen
            )
        }
    }

    private func buildAllNetworksSummaryMenu() {
        let menu = NSMenu()
        configure(menu: menu)
        menu.addItem(readOnlyItem(L10n.text("今日"), emphasized: true))
        let today = addUsageItems(to: menu)
        menu.addItem(.separator())
        menu.addItem(readOnlyItem(L10n.text("最近 7 天"), emphasized: true))
        let recentSevenDays = addUsageItems(to: menu)
        menu.addItem(.separator())
        menu.addItem(readOnlyItem(L10n.text("本月"), emphasized: true))
        let month = addUsageItems(to: menu)
        menu.addItem(.separator())
        menu.addItem(readOnlyItem(L10n.text("全部历史"), emphasized: true))
        let allTime = addUsageItems(to: menu)
        allNetworksItems = AllNetworksMenuItems(
            root: submenuItem(L10n.text("所有网络  0 B"), submenu: menu),
            today: today,
            recentSevenDays: recentSevenDays,
            month: month,
            allTime: allTime
        )
    }

    private func rebuildNetworksMenu(_ summaries: [NetworkSummary]) {
        networksMenu.removeAllItems()
        networkItems.removeAll()
        networkOrder = summaries.map(\.identity.key)
        networksMenu.addItem(allNetworksItems.root)
        networksMenu.addItem(allNetworksSeparator)

        guard !summaries.isEmpty else {
            networksMenu.addItem(readOnlyItem(L10n.text("暂无统计")))
            return
        }

        for summary in summaries {
            let menu = NSMenu()
            configure(menu: menu)

            menu.addItem(readOnlyItem(L10n.text("今日"), emphasized: true))
            let today = addUsageItems(to: menu)
            menu.addItem(.separator())

            menu.addItem(readOnlyItem(L10n.text("最近 7 天"), emphasized: true))
            let recentSevenDays = addUsageItems(to: menu)
            menu.addItem(.separator())

            menu.addItem(readOnlyItem(L10n.text("本月"), emphasized: true))
            let month = addUsageItems(to: menu)
            menu.addItem(.separator())

            menu.addItem(readOnlyItem(L10n.text("全部历史"), emphasized: true))
            let allTime = addUsageItems(to: menu)
            menu.addItem(.separator())

            let typeAndInterface = readOnlyItem("")
            let firstSeen = readOnlyItem("")
            menu.addItem(typeAndInterface)
            menu.addItem(firstSeen)

            let root = submenuItem("", submenu: menu)
            networksMenu.addItem(root)
            networkItems[summary.identity.key] = NetworkMenuItems(
                root: root,
                today: today,
                recentSevenDays: recentSevenDays,
                month: month,
                allTime: allTime,
                typeAndInterface: typeAndInterface,
                firstSeen: firstSeen
            )
        }
    }

    private func refreshSettings(allowStructureChanges: Bool) {
        launchAtLoginItem.state = model.launchAtLogin ? .on : .off
        trackWiFiItem.state = model.trackWiFi ? .on : .off
        trackEthernetItem.state = model.trackEthernet ? .on : .off
        refreshNetworkNamesMenu(allowStructureChanges: allowStructureChanges)
        setTitle(L10n.format("SSID 位置权限：{0}", model.locationStatus), on: locationStatusItem)

        if allowStructureChanges {
            requestLocationItem.isHidden = model.isLocationAuthorized
            let hasMessage = model.settingsMessage != nil
            settingsMessageSeparator.isHidden = !hasMessage
            settingsMessageItem.isHidden = !hasMessage
        }
        if let message = model.settingsMessage {
            setTitle(L10n.text(message), on: settingsMessageItem)
        }
    }

    private func refreshNetworkNamesMenu(allowStructureChanges: Bool) {
        let summaries = model.customizableNetworkSummaries
        let signature = summaries.map {
            "\($0.identity.key)\u{0}\($0.identity.displayName)" +
                "\u{0}\($0.identity.interfaceName)"
        }
        if signature != networkNameMenuSignature, allowStructureChanges {
            rebuildNetworkNamesMenu(summaries)
        }
    }

    private func rebuildNetworkNamesMenu(_ summaries: [NetworkSummary]) {
        networkNamesMenu.removeAllItems()
        networkNameMenuSignature = summaries.map {
            "\($0.identity.key)\u{0}\($0.identity.displayName)" +
                "\u{0}\($0.identity.interfaceName)"
        }

        guard !summaries.isEmpty else {
            networkNamesMenu.addItem(
                readOnlyItem(L10n.text("暂无 Wi-Fi、Ethernet 或 PPP 记录"))
            )
            return
        }

        for summary in summaries {
            let identity = summary.identity
            let defaultName = model.defaultNetworkName(for: identity)
            let prefix = "\(defaultName) · \(identity.interfaceName)"
            let title: String
            if let customName = model.customNetworkName(for: identity) {
                title = "\(prefix) → \(customName)"
            } else {
                title = prefix
            }

            let item = actionItem(
                title,
                action: #selector(customizeNetworkName(_:))
            )
            item.representedObject = identity.key
            networkNamesMenu.addItem(item)
        }
    }

    private func refreshDebug() {
        let debug = model.debug
        setTitle("Current SSID: \(debug.currentSSID)", on: debugSSIDItem)
        setTitle("Interface: \(debug.interfaceName)", on: debugInterfaceItem)
        setTitle("TX counter: \(raw(debug.transmittedCounter))", on: debugTXItem)
        setTitle("RX counter: \(raw(debug.receivedCounter))", on: debugRXItem)
        setTitle(
            "Previous TX: \(raw(debug.previousTransmitted))",
            on: debugPreviousTXItem
        )
        setTitle(
            "Previous RX: \(raw(debug.previousReceived))",
            on: debugPreviousRXItem
        )
        setTitle("Delta TX: \(debug.deltaUpload)", on: debugDeltaTXItem)
        setTitle("Delta RX: \(debug.deltaDownload)", on: debugDeltaRXItem)
        setTitle("State: \(L10n.text(debug.note))", on: debugStateItem)
        debugLoggingItem.state = model.debugLogging ? .on : .off
    }

    private func readOnlyItem(
        _ title: String,
        systemImage: String? = nil,
        emphasized: Bool = false,
        accessibilityTitle: String? = nil
    ) -> NSMenuItem {
        let item = NSMenuItem(
            title: title,
            action: #selector(noOp),
            keyEquivalent: ""
        )
        item.target = self
        item.isEnabled = true
        if let systemImage {
            item.image = symbol(systemImage, description: title)
        }
        if emphasized {
            item.attributedTitle = NSAttributedString(
                string: title,
                attributes: [
                    .font: NSFont.boldSystemFont(ofSize: NSFont.systemFontSize)
                ]
            )
        }
        item.setAccessibilityLabel(accessibilityTitle ?? title)
        item.setAccessibilityHelp(L10n.text("只读信息"))
        return item
    }

    private func actionItem(_ title: String, action: Selector) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        item.isEnabled = true
        return item
    }

    private func emphasizedSubmenuItem(
        _ title: String,
        submenu: NSMenu,
        accessibilityTitle: String
    ) -> NSMenuItem {
        let item = submenuItem(title, submenu: submenu)
        item.attributedTitle = NSAttributedString(
            string: title,
            attributes: [
                .font: NSFont.boldSystemFont(ofSize: NSFont.systemFontSize)
            ]
        )
        item.setAccessibilityLabel(accessibilityTitle)
        return item
    }

    private func submenuItem(
        _ title: String,
        systemImage: String? = nil,
        submenu: NSMenu
    ) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        if let systemImage {
            item.image = symbol(systemImage, description: title)
        }
        item.submenu = submenu
        item.isEnabled = true
        return item
    }

    private func symbol(_ name: String, description: String) -> NSImage? {
        let image = NSImage(
            systemSymbolName: name,
            accessibilityDescription: description
        )
        image?.isTemplate = true
        return image
    }

    private func setTitle(_ title: String, on item: NSMenuItem) {
        guard item.title != title else { return }
        item.title = title
        item.setAccessibilityLabel(title)
    }

    private func raw(_ value: UInt64?) -> String {
        value.map(String.init) ?? "—"
    }

    private func rebuildForLanguageIfNeeded() {
        guard needsLanguageRebuild, !isRootMenuOpen else { return }
        needsLanguageRebuild = false
        buildRootMenu()
        buildCurrentNetworkMenu()
        buildSettingsMenu()
        buildDebugMenu()
        buildAllNetworksSummaryMenu()
        rebuildNetworksMenu(model.summaries)
    }

    @objc private func selectLanguage(_ sender: NSMenuItem) {
        guard let value = sender.representedObject as? String,
              let language = AppLanguage(rawValue: value),
              language != L10n.language else { return }
        LanguagePreference().language = language
        needsLanguageRebuild = true
        for (choice, item) in languageItems {
            item.state = choice == language ? .on : .off
        }
        // AppKit can deliver the action before or after menuDidClose.
        DispatchQueue.main.async { [weak self] in
            guard let self, !self.isRootMenuOpen else { return }
            self.refreshMenu(allowStructureChanges: true)
        }
    }

    @objc private func noOp() {}

    @objc private func toggleLaunchAtLogin() {
        model.setLaunchAtLogin(!model.launchAtLogin)
        refreshMenu(allowStructureChanges: !isRootMenuOpen)
    }

    @objc private func toggleTrackWiFi() {
        model.setTrackWiFi(!model.trackWiFi)
        refreshMenu(allowStructureChanges: !isRootMenuOpen)
    }

    @objc private func toggleTrackEthernet() {
        model.setTrackEthernet(!model.trackEthernet)
        refreshMenu(allowStructureChanges: !isRootMenuOpen)
    }

    @objc private func toggleDebugLogging() {
        model.setDebugLogging(!model.debugLogging)
        refreshMenu(allowStructureChanges: !isRootMenuOpen)
    }

    @objc private func makeNetworkServicePreferred(_ sender: NSMenuItem) {
        guard let serviceID = sender.representedObject as? String else { return }
        DispatchQueue.main.async { [weak self] in
            self?.applyPreferredNetworkService(serviceID: serviceID)
        }
    }

    private func applyPreferredNetworkService(serviceID: String) {
        do {
            let snapshot = try networkServiceOrderManager.makePreferred(
                serviceID: serviceID
            )
            rebuildCurrentNetworkMenu(with: snapshot)
        } catch {
            let readbackDescription: String
            do {
                let actual = try networkServiceOrderManager.read()
                rebuildCurrentNetworkMenu(with: actual)
                readbackDescription = L10n.text("已重新读取并显示 macOS 当前实际服务顺序。")
            } catch let readbackError {
                showNetworkServiceReadFailure(readbackError)
                readbackDescription =
                    L10n.text("同时无法重新读取当前服务顺序：") +
                    readbackError.localizedDescription
            }
            presentNetworkServiceOrderError(
                error,
                readbackDescription: readbackDescription
            )
        }
    }

    private func presentNetworkServiceOrderError(
        _ error: Error,
        readbackDescription: String
    ) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = L10n.text("无法更改网络服务顺序")
        alert.informativeText =
            error.localizedDescription + "\n\n" + readbackDescription
        alert.addButton(withTitle: L10n.text("好"))
        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()
    }

    @objc private func openNetworkSettings() {
        let destinations = [
            "x-apple.systempreferences:com.apple.Network-Settings.extension",
            "x-apple.systempreferences:com.apple.preference.network",
        ]
        for destination in destinations {
            guard let url = URL(string: destination) else { continue }
            if NSWorkspace.shared.open(url) {
                return
            }
        }
    }

    @objc private func customizeNetworkName(_ sender: NSMenuItem) {
        guard let identityKey = sender.representedObject as? String,
              let summary = model.summaries.first(where: {
                  $0.identity.key == identityKey
              }) else { return }

        let textField = NSTextField(
            frame: NSRect(x: 0, y: 0, width: 240, height: 24)
        )
        textField.stringValue =
            model.customNetworkName(for: summary.identity) ?? ""
        textField.placeholderString = model.defaultNetworkName(
            for: summary.identity
        )

        let alert = NSAlert()
        alert.messageText = L10n.text("自定义网络名称")
        alert.informativeText =
            L10n.format("最多 {0} 个字符，", String(AppModel.maximumCustomNetworkNameLength)) +
            L10n.text("超出部分会自动截断；留空可恢复默认名称。")
        alert.accessoryView = textField
        alert.addButton(withTitle: L10n.text("保存"))
        alert.addButton(withTitle: L10n.text("取消"))

        NSApp.activate(ignoringOtherApps: true)
        alert.window.initialFirstResponder = textField
        guard alert.runModal() == .alertFirstButtonReturn else { return }

        model.setNetworkName(textField.stringValue, for: identityKey)
        refreshMenu(allowStructureChanges: true)
    }

    @objc private func requestLocationAccess() {
        model.requestLocationAccess()
    }

    @objc private func revealDatabase() {
        model.revealDatabase()
    }

    @objc private func revealDebugLog() {
        model.revealDebugLog()
    }

    @objc private func clearHistory() {
        model.clearHistory()
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.refreshMenu(allowStructureChanges: !self.isRootMenuOpen)
        }
    }

    @objc private func quitApplication() {
        model.stop()
        NSApplication.shared.terminate(nil)
    }
}
