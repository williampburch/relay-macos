// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "Relay",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "Relay", targets: ["Remote"])
    ],
    targets: [
        .executableTarget(
            name: "Remote",
            path: "Remote",
            exclude: [
                "RDP/FreeRDPBridge/README.md",
                "Resources"
            ]
        ),
        .testTarget(
            name: "RemoteTests",
            dependencies: ["Remote"],
            path: "RemoteTests"
        )
    ]
)
