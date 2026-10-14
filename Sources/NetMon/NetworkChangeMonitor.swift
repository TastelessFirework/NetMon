import CoreWLAN
import Foundation
import Network

struct NetworkPathHint {
    let physicalInterfaceName: String?
}

final class NetworkChangeMonitor: NSObject, CWEventDelegate {
    private let wifiClient = CWWiFiClient.shared()
    private let pathMonitor = NWPathMonitor()
    private let pathQueue = DispatchQueue(
        label: "com.eric.SSIDTrafficMonitor.path-monitor"
    )
    private let onChange: @MainActor (String, NetworkPathHint?) -> Void
    private var started = false

    init(onChange: @escaping @MainActor (String, NetworkPathHint?) -> Void) {
        self.onChange = onChange
        super.init()
    }

    func start() {
        guard !started else { return }
        started = true
        wifiClient.delegate = self
        try? wifiClient.startMonitoringEvent(with: .ssidDidChange)
        try? wifiClient.startMonitoringEvent(with: .linkDidChange)
        try? wifiClient.startMonitoringEvent(with: .powerDidChange)

        pathMonitor.pathUpdateHandler = { [weak self] path in
            guard let self else { return }
            let physicalName = path.availableInterfaces.first {
                $0.type == .wifi || $0.type == .wiredEthernet
            }?.name
            Task { @MainActor in
                self.onChange(
                    "network path changed",
                    NetworkPathHint(physicalInterfaceName: physicalName)
                )
            }
        }
        pathMonitor.start(queue: pathQueue)
    }

    func stop() {
        guard started else { return }
        started = false
        pathMonitor.cancel()
        try? wifiClient.stopMonitoringAllEvents()
        wifiClient.delegate = nil
    }

    func ssidDidChangeForWiFiInterface(withName interfaceName: String) {
        notify("SSID changed on \(interfaceName)")
    }

    func linkDidChangeForWiFiInterface(withName interfaceName: String) {
        notify("Wi-Fi link changed on \(interfaceName)")
    }

    func powerStateDidChangeForWiFiInterface(withName interfaceName: String) {
        notify("Wi-Fi power changed on \(interfaceName)")
    }

    private func notify(_ reason: String) {
        Task { @MainActor in
            onChange(reason, nil)
        }
    }
}
