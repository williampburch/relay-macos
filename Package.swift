// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "Remote",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "Remote", targets: ["Remote"])
    ],
    targets: [
        .executableTarget(
            name: "Remote",
            path: "Remote",
            exclude: [
                "RDP/FreeRDPBridge/README.md"
            ]
        ),
        .testTarget(
            name: "RemoteTests",
            dependencies: ["Remote"],
            path: "RemoteTests"
        )
    ]
)
