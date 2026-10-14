import Foundation
import NetMonCore
import Security
import SystemConfiguration

struct SystemNetworkServiceOrderSnapshot {
    let services: [OrderedNetworkService]

    var preferredServiceID: String? {
        services.first?.id
    }
}

private enum SystemNetworkServiceOrderFailure: LocalizedError {
    case authorization(OSStatus)
    case accessDenied(String)
    case configuration(String)
    case systemConfiguration(operation: String, code: Int32, detail: String)
    case verification(String)

    var errorDescription: String? {
        switch self {
        case .authorization(let status):
            let detail = SecCopyErrorMessageString(status, nil) as String?
                ?? L10n.format("错误码 {0}", String(status))
            return L10n.format("无法创建 macOS 授权会话：{0}。", detail)

        case .accessDenied(let operation):
            return L10n.format("管理员授权已取消或未通过，macOS 未允许{0}。", operation)

        case .configuration(let detail):
            return L10n.format("无法读取 macOS 网络服务顺序：{0}。", detail)

        case .systemConfiguration(let operation, let code, let detail):
            return L10n.format("macOS 未能{0}：{1}（错误码 {2}）。", operation, detail, String(code))

        case .verification(let detail):
            return L10n.format("系统报告配置已提交并应用，但重新读取时未能确认结果：{0}。", detail)
        }
    }
}

@MainActor
final class NetworkServiceOrderManager {
    private struct Configuration {
        let set: SCNetworkSet
        let systemOrder: [String]
        let snapshot: SystemNetworkServiceOrderSnapshot
    }

    func read() throws -> SystemNetworkServiceOrderSnapshot {
        guard let preferences = SCPreferencesCreate(
            nil,
            "NetMon" as CFString,
            nil
        ) else {
            throw lastFailure(operation: L10n.text("建立网络配置读取会话"))
        }
        return try configuration(in: preferences).snapshot
    }

    func makePreferred(
        serviceID: String
    ) throws -> SystemNetworkServiceOrderSnapshot {
        var authorization: AuthorizationRef?
        let authorizationStatus = AuthorizationCreate(
            nil,
            nil,
            [],
            &authorization
        )
        guard authorizationStatus == errAuthorizationSuccess,
              let authorization else {
            throw SystemNetworkServiceOrderFailure.authorization(
                authorizationStatus
            )
        }
        defer {
            AuthorizationFree(authorization, [.destroyRights])
        }

        guard let preferences = SCPreferencesCreateWithAuthorization(
            nil,
            "NetMon" as CFString,
            nil,
            authorization
        ) else {
            throw lastFailure(operation: L10n.text("建立已授权的网络配置会话"))
        }

        let current = try configuration(in: preferences)
        let newOrder: [String]
        do {
            newOrder = try NetworkServiceOrderLogic.movingToFront(
                serviceID: serviceID,
                systemOrder: current.systemOrder
            )
        } catch {
            throw SystemNetworkServiceOrderFailure.configuration(
                L10n.text("所选服务已不在当前系统服务顺序中")
            )
        }

        if newOrder == current.systemOrder {
            return current.snapshot
        }

        guard SCNetworkSetSetServiceOrder(current.set, newOrder as CFArray)
        else {
            throw lastFailure(operation: L10n.text("保存新的网络服务顺序"))
        }
        guard SCPreferencesCommitChanges(preferences) else {
            throw lastFailure(operation: L10n.text("提交网络服务顺序"))
        }
        guard SCPreferencesApplyChanges(preferences) else {
            throw lastFailure(operation: L10n.text("应用网络服务顺序"))
        }

        let verified = try read()
        guard verified.preferredServiceID == serviceID else {
            throw SystemNetworkServiceOrderFailure.verification(
                L10n.text("首位服务仍不是所选服务")
            )
        }
        return verified
    }

    private func configuration(
        in preferences: SCPreferences
    ) throws -> Configuration {
        guard let set = SCNetworkSetCopyCurrent(preferences) else {
            throw SystemNetworkServiceOrderFailure.configuration(
                L10n.text("当前没有可用的 network set")
            )
        }
        guard let rawServices = SCNetworkSetCopyServices(set)
                as? [SCNetworkService] else {
            throw SystemNetworkServiceOrderFailure.configuration(
                L10n.text("当前 network set 没有可读取的服务列表")
            )
        }
        guard let systemOrder = SCNetworkSetGetServiceOrder(set)
                as? [String] else {
            throw SystemNetworkServiceOrderFailure.configuration(
                L10n.text("当前 network set 没有可读取的服务顺序")
            )
        }

        var rawServicesByID: [String: SCNetworkService] = [:]
        for service in rawServices {
            guard let serviceID = SCNetworkServiceGetServiceID(service)
                    as String?,
                  !serviceID.isEmpty else {
                continue
            }
            guard rawServicesByID.updateValue(service, forKey: serviceID) == nil
            else {
                throw SystemNetworkServiceOrderFailure.configuration(
                    L10n.format("系统返回了重复的服务 ID {0}", serviceID)
                )
            }
        }

        let services = try systemOrder.map { serviceID in
            guard let service = rawServicesByID[serviceID] else {
                throw SystemNetworkServiceOrderFailure.configuration(
                    L10n.text("服务顺序引用了当前服务列表中不存在的 ID")
                )
            }
            guard let name = SCNetworkServiceGetName(service) as String?,
                  !name.isEmpty else {
                throw SystemNetworkServiceOrderFailure.configuration(
                    L10n.format("服务 {0} 缺少系统显示名称", serviceID)
                )
            }
            return OrderedNetworkService(
                id: serviceID,
                name: name,
                isEnabled: SCNetworkServiceGetEnabled(service)
            )
        }

        let orderedServices: [OrderedNetworkService]
        do {
            orderedServices = try NetworkServiceOrderLogic.orderedServices(
                systemOrder: systemOrder,
                availableServices: services
            )
        } catch {
            throw SystemNetworkServiceOrderFailure.configuration(
                L10n.text("系统服务列表与服务顺序暂时不一致")
            )
        }

        return Configuration(
            set: set,
            systemOrder: systemOrder,
            snapshot: SystemNetworkServiceOrderSnapshot(
                services: orderedServices
            )
        )
    }

    private func lastFailure(
        operation: String
    ) -> SystemNetworkServiceOrderFailure {
        let code = SCError()
        if code == kSCStatusAccessError {
            return .accessDenied(operation)
        }
        let detail = String(cString: SCErrorString(code))
        return .systemConfiguration(
            operation: operation,
            code: code,
            detail: detail
        )
    }
}
