import CNetworkStats
import Foundation
import NetMonCore

enum SystemCounterError: Error, LocalizedError {
    case readFailed(interface: String, code: Int32)

    var errorDescription: String? {
        switch self {
        case .readFailed(let interface, let code):
            return "无法读取 \(interface) 的接口计数器（错误 \(code)）"
        }
    }
}

struct SystemCounterReader {
    func read(interfaceName: String) throws -> InterfaceCounters {
        var raw = nm_interface_counters()
        let status = nm_read_interface_counters(interfaceName, &raw)
        guard status == 0 else {
            throw SystemCounterError.readFailed(
                interface: interfaceName,
                code: status
            )
        }
        return InterfaceCounters(
            received: raw.received_bytes,
            transmitted: raw.transmitted_bytes
        )
    }
}
