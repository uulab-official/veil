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
        ),
        .executable(
            name: "veil-vmctl",
            targets: ["VeilVMControl"]
        ),
        .executable(
            name: "veil-app-launcher",
            targets: ["VeilAppLauncher"]
        )
    ],
    dependencies: [
        // Updates of Veil itself; see docs/release-updates.md.
        .package(url: "https://github.com/sparkle-project/Sparkle", exact: "2.10.1")
    ],
    targets: [
        .target(
            name: "VeilHostCore"
        ),
        .executableTarget(
            name: "VeilHostProbe",
            dependencies: ["VeilHostCore"]
        ),
        // Shared by Veil and the per-app launchers it generates; kept free of VeilHostCore so each
        // launcher binary stays small.
        .target(
            name: "VeilLauncherSupport"
        ),
        .executableTarget(
            name: "VeilAppLauncher",
            dependencies: ["VeilLauncherSupport"]
        ),
        .executableTarget(
            name: "VeilHostShell",
            dependencies: [
                "VeilHostCore",
                "VeilLauncherSupport",
                .product(name: "Sparkle", package: "Sparkle")
            ],
            resources: [
                .copy("Resources/VeilAppIcon.icns")
            ]
        ),
        .executableTarget(
            name: "VeilVMControl",
            dependencies: ["VeilHostCore"]
        ),
        .testTarget(
            name: "VeilHostCoreTests",
            dependencies: ["VeilHostCore"],
            resources: [
                .process("Fixtures")
            ]
        ),
        .testTarget(
            name: "VeilHostShellTests",
            dependencies: ["VeilHostCore", "VeilHostShell", "VeilLauncherSupport"]
        )
    ]
)
