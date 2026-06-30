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
        ),
        .executable(
            name: "veil-host-shell",
            targets: ["VeilHostShell"]
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
        .executableTarget(
            name: "VeilHostShell",
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
