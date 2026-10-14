// swift-tools-version: 5.10

import PackageDescription

let package = Package(
    name: "NetMon",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "NetMon", targets: ["NetMon"])
    ],
    targets: [
        .target(
            name: "CNetworkStats",
            publicHeadersPath: "include"
        ),
        .target(
            name: "NetMonCore",
            linkerSettings: [
                .linkedLibrary("sqlite3")
            ]
        ),
        .executableTarget(
            name: "NetMon",
            dependencies: ["CNetworkStats", "NetMonCore"],
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("CoreLocation"),
                .linkedFramework("CoreWLAN"),
                .linkedFramework("Network"),
                .linkedFramework("Security"),
                .linkedFramework("ServiceManagement"),
                .linkedFramework("SystemConfiguration")
            ]
        ),
        .testTarget(
            name: "NetMonCoreTests",
            dependencies: ["CNetworkStats", "NetMonCore"]
        )
    ]
)
