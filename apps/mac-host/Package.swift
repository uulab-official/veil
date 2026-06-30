// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "VeilMacHost",
    platforms: [
        .macOS(.v15)
    ],
    products: [
        .library(
            name: "VeilHostCore",
            targets: ["VeilHostCore"]
        ),
        .executable(
            name: "veil-host-probe",
            targets: ["VeilHostProbe"]
        )
    ],
    targets: [
        .target(
            name: "VeilHostCore"
        ),
        .executableTarget(
            name: "VeilHostProbe",
            dependencies: ["VeilHostCore"]
        ),
        .testTarget(
            name: "VeilHostCoreTests",
            dependencies: ["VeilHostCore"],
            resources: [
                .process("Fixtures")
            ]
        )
    ]
)
