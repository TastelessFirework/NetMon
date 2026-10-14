import Testing
@testable import NetMonCore

@Suite("Network type capabilities")
struct NetworkKindTests {
    @Test("Wi-Fi, Ethernet, and PPP support custom names")
    func customNameSupport() {
        #expect(NetworkKind.wifi.supportsCustomName)
        #expect(NetworkKind.ethernet.supportsCustomName)
        #expect(NetworkKind.ppp.supportsCustomName)
        #expect(!NetworkKind.vpn.supportsCustomName)
        #expect(!NetworkKind.other.supportsCustomName)
    }
}
