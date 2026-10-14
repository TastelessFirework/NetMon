import CoreWLAN
import Foundation
import NetMonCore
import SystemConfiguration

struct NetworkResolution {
    let identity: NetworkIdentity?
    let interfaceName: String?
    let issue: String?
}

struct InterfaceDescriptor {
    let bsdName: String
    let type: String
    let localizedName: String?
}

final class NetworkResolver {
    private let wifiClient = CWWiFiClient.shared()
    private var underlyingPhysicalInterfaceName: String?

    func setUnderlyingPhysicalInterface(_ interfaceName: String?) {
        underlyingPhysicalInterfaceName = interfaceName
    }

    func resolve() -> NetworkResolution {
        guard var interfaceName = primaryInterfaceName() else {
            return NetworkResolution(
                identity: nil,
                interfaceName: nil,
                issue: "当前没有可用的主网络接口"
            )
        }

        let descriptors = interfaceDescriptors()
        var descriptor = descriptors[interfaceName]
        var kind = classify(interfaceName: interfaceName, descriptor: descriptor)

        // A utun route is a logical overlay. For the requested "which Wi-Fi
        // consumed the bytes" view, sample the physical interface carrying the
        // tunnel instead of grouping everything under the VPN device.
        if kind == .vpn,
           let physicalName = underlyingPhysicalInterfaceName,
           let physicalDescriptor = descriptors[physicalName] {
            let physicalKind = classify(
                interfaceName: physicalName,
                descriptor: physicalDescriptor
            )
            if physicalKind == .wifi || physicalKind == .ethernet {
                interfaceName = physicalName
                descriptor = physicalDescriptor
                kind = physicalKind
            }
        }

        if kind == .wifi {
            guard let ssid = wifiClient.interface(withName: interfaceName)?.ssid(),
                  !ssid.isEmpty else {
                return NetworkResolution(
                    identity: nil,
                    interfaceName: interfaceName,
                    issue: "无法读取 Wi-Fi 名称；请允许位置权限"
                )
            }
            return NetworkResolution(
                identity: NetworkIdentity(
                    key: "wifi:\(ssid)",
                    displayName: ssid,
                    ssid: ssid,
                    kind: .wifi,
                    interfaceName: interfaceName
                ),
                interfaceName: interfaceName,
                issue: nil
            )
        }

        let displayName: String
        switch kind {
        case .ethernet:
            displayName = "Ethernet"
        case .ppp:
            displayName = "PPP"
        case .vpn:
            displayName = "VPN"
        case .other:
            displayName = descriptor?.localizedName ?? "其他网络"
        case .wifi:
            displayName = "Wi-Fi"
        }

        let key = "\(kind.rawValue):\(interfaceName):\(displayName)"
        return NetworkResolution(
            identity: NetworkIdentity(
                key: key,
                displayName: displayName,
                ssid: nil,
                kind: kind,
                interfaceName: interfaceName
            ),
            interfaceName: interfaceName,
            issue: nil
        )
    }

    private func primaryInterfaceName() -> String? {
        let keys = [
            "State:/Network/Global/IPv4",
            "State:/Network/Global/IPv6"
        ]
        for key in keys {
            guard let value = SCDynamicStoreCopyValue(nil, key as CFString)
                    as? [String: Any] else {
                continue
            }
            if let name = value["PrimaryInterface"] as? String,
               !name.isEmpty {
                return name
            }
        }
        return nil
    }

    private func interfaceDescriptors() -> [String: InterfaceDescriptor] {
        guard let rawInterfaces = SCNetworkInterfaceCopyAll() as? [SCNetworkInterface]
        else { return [:] }

        var result: [String: InterfaceDescriptor] = [:]
        for interface in rawInterfaces {
            guard let bsdName = SCNetworkInterfaceGetBSDName(interface) as String?
            else { continue }
            let type = SCNetworkInterfaceGetInterfaceType(interface) as String? ?? ""
            let localizedName = SCNetworkInterfaceGetLocalizedDisplayName(interface)
                as String?
            result[bsdName] = InterfaceDescriptor(
                bsdName: bsdName,
                type: type,
                localizedName: localizedName
            )
        }
        return result
    }

    private func classify(
        interfaceName: String,
        descriptor: InterfaceDescriptor?
    ) -> NetworkKind {
        let type = descriptor?.type ?? ""
        if type == (kSCNetworkInterfaceTypeIEEE80211 as String) {
            return .wifi
        }
        if type == (kSCNetworkInterfaceTypeEthernet as String) ||
            type.localizedCaseInsensitiveContains("ethernet") {
            return .ethernet
        }
        if type == (kSCNetworkInterfaceTypePPP as String) ||
            interfaceName.hasPrefix("ppp") {
            return .ppp
        }
        if interfaceName.hasPrefix("utun") ||
            type.localizedCaseInsensitiveContains("vpn") ||
            type.localizedCaseInsensitiveContains("ipsec") {
            return .vpn
        }

        // CoreWLAN is a useful fallback when SystemConfiguration doesn't expose
        // a descriptor for an interface during a transition.
        if wifiClient.interfaceNames()?.contains(interfaceName) == true {
            return .wifi
        }
        return .other
    }
}
