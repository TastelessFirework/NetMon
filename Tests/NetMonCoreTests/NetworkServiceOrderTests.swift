import Testing
@testable import NetMonCore

@Suite("macOS network service ordering")
struct NetworkServiceOrderTests {
    private let wifi = OrderedNetworkService(
        id: "wifi-id",
        name: "Wi-Fi",
        isEnabled: true
    )
    private let ethernet = OrderedNetworkService(
        id: "ethernet-id",
        name: "Office Ethernet",
        isEnabled: true
    )
    private let ppp = OrderedNetworkService(
        id: "ppp-id",
        name: "PPPoE",
        isEnabled: false
    )

    @Test("Candidates follow the macOS service order, not discovery order")
    func candidatesFollowSystemOrder() throws {
        let ordered = try NetworkServiceOrderLogic.orderedServices(
            systemOrder: [ppp.id, wifi.id, ethernet.id],
            availableServices: [ethernet, ppp, wifi]
        )

        #expect(ordered == [ppp, wifi, ethernet])
    }

    @Test("Services outside the current service order are not candidates")
    func unorderedServicesAreExcluded() throws {
        let ordered = try NetworkServiceOrderLogic.orderedServices(
            systemOrder: [wifi.id, ethernet.id],
            availableServices: [ppp, ethernet, wifi]
        )

        #expect(ordered == [wifi, ethernet])
    }

    @Test("An inconsistent system snapshot is rejected instead of truncated")
    func missingOrderedServiceFails() {
        #expect(
            throws: NetworkServiceOrderError.missingOrderedService("gone-id")
        ) {
            try NetworkServiceOrderLogic.orderedServices(
                systemOrder: [wifi.id, "gone-id"],
                availableServices: [wifi, ethernet]
            )
        }
    }

    @Test("Promoting a service preserves every other relative position")
    func promotePreservesRelativeOrder() throws {
        let reordered = try NetworkServiceOrderLogic.movingToFront(
            serviceID: ppp.id,
            systemOrder: [wifi.id, ethernet.id, ppp.id]
        )

        #expect(reordered == [ppp.id, wifi.id, ethernet.id])
    }

    @Test("A stale selection cannot create a fabricated service order")
    func staleSelectionFails() {
        #expect(throws: NetworkServiceOrderError.unavailableService("old-id")) {
            try NetworkServiceOrderLogic.movingToFront(
                serviceID: "old-id",
                systemOrder: [wifi.id, ethernet.id]
            )
        }
    }
}
