import CNetworkStats
import Testing

@Suite("Darwin interface counters")
struct SystemCounterSmokeTests {
    @Test("NET_RT_IFLIST2 exposes 64-bit loopback counters")
    func readsLoopback() {
        var counters = nm_interface_counters()
        let status = nm_read_interface_counters("lo0", &counters)
        #expect(status == 0)
        #expect(counters.is_up != 0)
    }
}
