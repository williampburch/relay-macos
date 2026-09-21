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
    dependencies: [
        .package(
            url: "https://github.com/migueldeicaza/SwiftTerm.git",
            exact: "1.17.0"
        )
    ],
    targets: [
        .executableTarget(
            name: "Remote",
            dependencies: [
                .product(name: "SwiftTerm", package: "SwiftTerm")
            ],
            path: "Remote",
            exclude: [
                "RDP/FreeRDPBridge/README.md",
                "Relay-Info.plist",
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
