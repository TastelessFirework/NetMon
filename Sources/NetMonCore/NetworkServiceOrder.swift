import Foundation

public struct OrderedNetworkService: Equatable, Sendable {
    public let id: String
    public let name: String
    public let isEnabled: Bool

    public init(id: String, name: String, isEnabled: Bool) {
        self.id = id
        self.name = name
        self.isEnabled = isEnabled
    }
}

public enum NetworkServiceOrderError: Error, Equatable, Sendable {
    case duplicateServiceID(String)
    case duplicateOrderID(String)
    case missingOrderedService(String)
    case unavailableService(String)
}

public enum NetworkServiceOrderLogic {
    public static func orderedServices(
        systemOrder: [String],
        availableServices: [OrderedNetworkService]
    ) throws -> [OrderedNetworkService] {
        var servicesByID: [String: OrderedNetworkService] = [:]
        for service in availableServices {
            guard servicesByID.updateValue(service, forKey: service.id) == nil
            else {
                throw NetworkServiceOrderError.duplicateServiceID(service.id)
            }
        }

        var seenOrderIDs = Set<String>()
        return try systemOrder.map { serviceID in
            guard seenOrderIDs.insert(serviceID).inserted else {
                throw NetworkServiceOrderError.duplicateOrderID(serviceID)
            }
            guard let service = servicesByID[serviceID] else {
                throw NetworkServiceOrderError.missingOrderedService(serviceID)
            }
            return service
        }
    }

    public static func movingToFront(
        serviceID: String,
        systemOrder: [String]
    ) throws -> [String] {
        guard systemOrder.contains(serviceID) else {
            throw NetworkServiceOrderError.unavailableService(serviceID)
        }

        var seenOrderIDs = Set<String>()
        for existingID in systemOrder {
            guard seenOrderIDs.insert(existingID).inserted else {
                throw NetworkServiceOrderError.duplicateOrderID(existingID)
            }
        }

        return [serviceID] + systemOrder.filter { $0 != serviceID }
    }
}
