import NetMonCore
import AppKit
import CoreLocation
import Foundation

@MainActor
final class LocationAccess: NSObject, CLLocationManagerDelegate {
    private let manager = CLLocationManager()
    var onAuthorizationChange: (() -> Void)?

    override init() {
        super.init()
        manager.delegate = self
    }

    var status: CLAuthorizationStatus {
        manager.authorizationStatus
    }

    var isAuthorized: Bool {
        switch status {
        case .authorized, .authorizedAlways, .authorizedWhenInUse:
            return true
        default:
            return false
        }
    }

    var statusText: String {
        switch status {
        case .notDetermined: return L10n.text("尚未请求")
        case .restricted: return L10n.text("受系统限制")
        case .denied: return L10n.text("已拒绝")
        case .authorized, .authorizedAlways, .authorizedWhenInUse:
            return L10n.text("已允许")
        @unknown default: return L10n.text("未知")
        }
    }

    func request() {
        if status == .notDetermined {
            NSApp.activate(ignoringOtherApps: true)
            manager.requestWhenInUseAuthorization()
        } else if status == .denied || status == .restricted {
            if let url = URL(
                string: "x-apple.systempreferences:com.apple.preference.security?Privacy_LocationServices"
            ) {
                NSWorkspace.shared.open(url)
            }
        }
    }

    nonisolated func locationManagerDidChangeAuthorization(
        _ manager: CLLocationManager
    ) {
        Task { @MainActor in
            onAuthorizationChange?()
        }
    }
}
