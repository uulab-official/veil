import Foundation
import Testing

@testable import VeilHostCore

@Suite("QEMU Windows boot plan")
struct QEMUWindowsBootPlanTests {
    @Test("builds a Windows 11 Arm install plan")
    func buildsWindowsArmInstallPlan() throws {
        var profile = VMProfile.defaultWindows11Arm(createdAt: Date(timeIntervalSince1970: 1_782_752_400))
        profile.installerMediaPath = "/Users/test/Downloads/Win11_25H2_Korean_Arm64_v2.iso"
        profile.virtualDiskPath = "/Users/test/Virtual Machines/Veil/Windows 11 Arm.img"
        profile.sharedFolderPath = "/Users/test/Veil Shared"
        profile.cpuCount = 8
        profile.memoryMB = 12_288

        let planner = QEMUWindowsBootPlanner(
            executablePath: "/opt/homebrew/bin/qemu-system-aarch64",
            isExecutableAvailable: true,
            firmwarePath: "/opt/homebrew/share/qemu/edk2-aarch64-code.fd",
            isFirmwareAvailable: true,
            firmwareVarsTemplatePath: "/opt/homebrew/share/qemu/edk2-arm-vars.fd",
            isFirmwareVarsTemplateAvailable: true,
            firmwareVarsPath: "/Users/test/Virtual Machines/Veil/uefi-vars.fd",
            isSecureBootFirmwareAvailable: false,
            tpmEmulatorPath: "/opt/homebrew/bin/swtpm",
            isTPMEmulatorAvailable: true,
            tpmStateDirectoryPath: "/Users/test/Virtual Machines/Veil/tpm"
        )

        let plan = try planner.makePlan(for: profile)

        #expect(plan.executablePath == "/opt/homebrew/bin/qemu-system-aarch64")
        #expect(plan.isExecutableAvailable)
        #expect(plan.firmwarePath == "/opt/homebrew/share/qemu/edk2-aarch64-code.fd")
        #expect(plan.isFirmwareAvailable)
        #expect(plan.firmwareVarsTemplatePath == "/opt/homebrew/share/qemu/edk2-arm-vars.fd")
        #expect(plan.isFirmwareVarsTemplateAvailable)
        #expect(plan.firmwareVarsPath == "/Users/test/Virtual Machines/Veil/uefi-vars.fd")
        #expect(plan.isSecureBootFirmwareAvailable == false)
        #expect(plan.tpmEmulatorPath == "/opt/homebrew/bin/swtpm")
        #expect(plan.isTPMEmulatorAvailable)
        #expect(plan.tpmStateDirectoryPath == "/Users/test/Virtual Machines/Veil/tpm")
        #expect(plan.arguments.containsSequence(["-machine", "virt,highmem=on"]))
        #expect(plan.arguments.containsSequence(["-accel", "hvf"]))
        #expect(plan.arguments.containsSequence(["-drive", "if=pflash,format=raw,readonly=on,file=/opt/homebrew/share/qemu/edk2-aarch64-code.fd"]))
        #expect(plan.arguments.containsSequence(["-drive", "if=pflash,format=raw,file=/Users/test/Virtual Machines/Veil/uefi-vars.fd"]))
        #expect(!plan.arguments.contains("-bios"))
        #expect(plan.arguments.containsSequence(["-chardev", "socket,id=chrtpm,path=/Users/test/Virtual Machines/Veil/tpm/swtpm.sock"]))
        #expect(plan.arguments.containsSequence(["-tpmdev", "emulator,id=tpm0,chardev=chrtpm"]))
        #expect(plan.arguments.containsSequence(["-device", "tpm-tis-device,tpmdev=tpm0"]))
        #expect(plan.arguments.containsSequence(["-boot", "order=d"]))
        #expect(plan.arguments.containsSequence(["-cpu", "host"]))
        #expect(plan.arguments.containsSequence(["-smp", "8"]))
        #expect(plan.arguments.containsSequence(["-m", "12288M"]))
        #expect(plan.arguments.contains("driver=raw,file.driver=file,file.locking=off,file.filename=/Users/test/Downloads/Win11_25H2_Korean_Arm64_v2.iso,if=none,id=installer,media=cdrom,readonly=on"))
        #expect(plan.automaticInstallMediaPath == "/Users/test/Veil Shared/VeilAutoInstall.iso")
        #expect(plan.arguments.contains("driver=raw,file.driver=file,file.locking=off,file.filename=/Users/test/Veil Shared/VeilAutoInstall.iso,if=none,id=autounattend,media=cdrom,readonly=on"))
        #expect(plan.arguments.contains("if=none,id=system,format=raw,file=/Users/test/Virtual Machines/Veil/Windows 11 Arm.img"))
        #expect(plan.arguments.containsSequence(["-device", "nvme,drive=system,serial=veil-system"]))
        #expect(!plan.arguments.containsSequence(["-device", "virtio-blk-pci,drive=system"]))
        #expect(plan.arguments.containsSequence(["-netdev", "user,id=net0,hostfwd=tcp::18444-:18444"]))
        #expect(plan.arguments.containsSequence(["-device", "virtio-net-pci,netdev=net0"]))
        #expect(plan.arguments.containsSequence(["-display", "cocoa"]))
        #expect(plan.arguments.containsSequence(["-device", "qemu-xhci,id=usb0"]))
        #expect(plan.arguments.containsSequence(["-device", "usb-storage,drive=autounattend"]))
        #expect(plan.arguments.containsSequence(["-device", "virtio-rng-pci"]))
        #expect(plan.arguments.contains("ramfb"))
        #expect(plan.arguments.contains("virtio-gpu-pci"))
        #expect(plan.arguments.contains("usb-kbd"))
        #expect(plan.arguments.contains("usb-tablet"))
        #expect(plan.warnings.isEmpty)
    }

    @Test("rejects profiles without installer media")
    func rejectsMissingInstallerMedia() {
        var profile = VMProfile.defaultWindows11Arm(createdAt: Date(timeIntervalSince1970: 1_782_752_400))
        profile.virtualDiskPath = "/Users/test/Virtual Machines/Veil/Windows 11 Arm.img"

        let planner = QEMUWindowsBootPlanner(
            executablePath: "/opt/homebrew/bin/qemu-system-aarch64",
            isExecutableAvailable: true,
            firmwarePath: "/opt/homebrew/share/qemu/edk2-aarch64-code.fd",
            isFirmwareAvailable: true,
            firmwareVarsTemplatePath: "/opt/homebrew/share/qemu/edk2-arm-vars.fd",
            isFirmwareVarsTemplateAvailable: true,
            firmwareVarsPath: "/Users/test/Virtual Machines/Veil/uefi-vars.fd",
            isSecureBootFirmwareAvailable: false,
            tpmEmulatorPath: "/opt/homebrew/bin/swtpm",
            isTPMEmulatorAvailable: true,
            tpmStateDirectoryPath: "/Users/test/Virtual Machines/Veil/tpm"
        )

        #expect(throws: QEMUWindowsBootPlanError.missingInstallerMedia) {
            _ = try planner.makePlan(for: profile)
        }
    }

    @Test("warns when QEMU executable is unavailable")
    func warnsWhenExecutableUnavailable() throws {
        var profile = VMProfile.defaultWindows11Arm(createdAt: Date(timeIntervalSince1970: 1_782_752_400))
        profile.installerMediaPath = "/Users/test/Downloads/Win11_25H2_Korean_Arm64_v2.iso"
        profile.virtualDiskPath = "/Users/test/Virtual Machines/Veil/Windows 11 Arm.img"
        profile.sharedFolderPath = "/Users/test/Veil Shared"

        let planner = QEMUWindowsBootPlanner(
            executablePath: "/opt/homebrew/bin/qemu-system-aarch64",
            isExecutableAvailable: false,
            firmwarePath: "/opt/homebrew/share/qemu/edk2-aarch64-code.fd",
            isFirmwareAvailable: true
        )

        let plan = try planner.makePlan(for: profile)

        #expect(plan.isExecutableAvailable == false)
        #expect(plan.warnings.contains("qemu-system-aarch64 is not available at /opt/homebrew/bin/qemu-system-aarch64. Install QEMU locally or set VEIL_QEMU_SYSTEM_AARCH64 before executing this plan."))
    }

    @Test("doctor passes when every QEMU prerequisite is ready")
    func doctorPassesWhenReady() throws {
        var profile = VMProfile.defaultWindows11Arm(createdAt: Date(timeIntervalSince1970: 1_782_752_400))
        profile.installerMediaPath = "/Users/test/Downloads/Win11_25H2_Korean_Arm64_v2.iso"
        profile.virtualDiskPath = "/Users/test/Virtual Machines/Veil/Windows 11 Arm.img"
        profile.sharedFolderPath = "/Users/test/Veil Shared"

        let planner = QEMUWindowsBootPlanner(
            executablePath: "/opt/homebrew/bin/qemu-system-aarch64",
            isExecutableAvailable: true,
            firmwarePath: "/opt/homebrew/share/qemu/edk2-aarch64-code.fd",
            isFirmwareAvailable: true,
            firmwareVarsTemplatePath: "/opt/homebrew/share/qemu/edk2-arm-vars.fd",
            isFirmwareVarsTemplateAvailable: true,
            firmwareVarsPath: "/Users/test/Virtual Machines/Veil/uefi-vars.fd",
            isSecureBootFirmwareAvailable: false,
            tpmEmulatorPath: "/opt/homebrew/bin/swtpm",
            isTPMEmulatorAvailable: true,
            tpmStateDirectoryPath: "/Users/test/Virtual Machines/Veil/tpm"
        )
        let plan = try planner.makePlan(for: profile)
        let doctor = QEMUWindowsReadinessDoctor(
            fileExists: { path in
                path == "/Users/test/Downloads/Win11_25H2_Korean_Arm64_v2.iso"
                    || path == "/Users/test/Veil Shared/VeilAutoInstall.iso"
                    || path == "/Users/test/Virtual Machines/Veil/Windows 11 Arm.img"
                    || path == "/opt/homebrew/bin/qemu-system-aarch64"
                    || path == "/opt/homebrew/share/qemu/edk2-aarch64-code.fd"
                    || path == "/opt/homebrew/share/qemu/edk2-arm-vars.fd"
                    || path == "/Users/test/Virtual Machines/Veil/uefi-vars.fd"
                    || path == "/opt/homebrew/bin/swtpm"
                    || path == "/Users/test/Virtual Machines/Veil/tpm"
            }
        )

        let report = doctor.makeReport(profile: profile, plan: plan)

        #expect(report.overallState == .ready)
        #expect(report.isServerBacked == false)
        #expect(report.checks.map(\.id) == [
            "vm-profile",
            "installer-media",
            "automatic-install-media",
            "system-disk",
            "qemu-executable",
            "uefi-firmware",
            "secure-boot",
            "tpm-emulator",
            "hvf-plan"
        ])
        #expect(report.checks.filter { $0.id != "secure-boot" }.allSatisfy { $0.state == .passed })
        #expect(report.checks.first { $0.id == "secure-boot" }?.state == .warning)
        #expect(report.nextActions.contains("Run veil-vmctl qemu-start to launch the local QEMU/HVF Windows setup window."))
        #expect(report.nextActions.contains("Run veil-vmctl qemu-smoke --json --seconds 120 and confirm Windows Setup no longer reports Secure Boot before marking Secure Boot support complete."))
    }

    @Test("local QEMU plan factory discovers swtpm and derives TPM state next to the disk")
    func localQEMUPlanFactoryDiscoversTPM() throws {
        var profile = VMProfile.defaultWindows11Arm(createdAt: Date(timeIntervalSince1970: 1_782_752_400))
        profile.installerMediaPath = "/Users/test/Downloads/Win11_25H2_Korean_Arm64_v2.iso"
        profile.virtualDiskPath = "/Users/test/Virtual Machines/Veil/Windows 11 Arm.img"
        profile.sharedFolderPath = "/Users/test/Veil Shared"

        let plan = try LocalQEMUWindowsBootPlanFactory.makePlan(
            for: profile,
            architecture: "arm64",
            minimumOSSupported: true,
            providerProbe: VMRuntimeProviderProbe(
                environment: [:],
                fileExists: { $0 == "/opt/homebrew/bin/qemu-system-aarch64" },
                executableVersion: { _ in "QEMU emulator version 11.0.2" }
            ),
            fileExists: { path in
                path == "/opt/homebrew/share/qemu/edk2-aarch64-code.fd"
                    || path == "/opt/homebrew/share/qemu/edk2-arm-vars.fd"
                    || path == "/Users/test/Virtual Machines/Veil/uefi-vars.fd"
                    || path == "/opt/homebrew/bin/swtpm"
            }
        )

        #expect(plan.firmwareVarsTemplatePath == "/opt/homebrew/share/qemu/edk2-arm-vars.fd")
        #expect(plan.isFirmwareVarsTemplateAvailable)
        #expect(plan.firmwareVarsPath == "/Users/test/Virtual Machines/Veil/uefi-vars.fd")
        #expect(plan.arguments.containsSequence(["-drive", "if=pflash,format=raw,file=/Users/test/Virtual Machines/Veil/uefi-vars.fd"]))
        #expect(plan.tpmEmulatorPath == "/opt/homebrew/bin/swtpm")
        #expect(plan.isTPMEmulatorAvailable)
        #expect(plan.tpmStateDirectoryPath == "/Users/test/Virtual Machines/Veil/tpm")
        #expect(plan.arguments.containsSequence(["-device", "tpm-tis-device,tpmdev=tpm0"]))
    }

    @Test("local QEMU plan factory keeps Secure Boot incomplete when only secure vars are available")
    func localQEMUPlanFactoryKeepsSecureBootIncompleteWithOnlySecureVars() throws {
        var profile = VMProfile.defaultWindows11Arm(createdAt: Date(timeIntervalSince1970: 1_782_752_400))
        profile.installerMediaPath = "/Users/test/Downloads/Win11_25H2_Korean_Arm64_v2.iso"
        profile.virtualDiskPath = "/Users/test/Virtual Machines/Veil/Windows 11 Arm.img"
        profile.sharedFolderPath = "/Users/test/Veil Shared"

        let plan = try LocalQEMUWindowsBootPlanFactory.makePlan(
            for: profile,
            architecture: "arm64",
            minimumOSSupported: true,
            providerProbe: VMRuntimeProviderProbe(
                environment: [:],
                fileExists: { $0 == "/opt/homebrew/bin/qemu-system-aarch64" },
                executableVersion: { _ in "QEMU emulator version 11.0.2" }
            ),
            fileExists: { path in
                path == "/opt/homebrew/share/qemu/edk2-aarch64-code.fd"
                    || path == "/Users/test/Library/Application Support/Veil/Firmware/edk2-arm-secure-vars.fd"
                    || path == "/opt/homebrew/share/qemu/edk2-arm-vars.fd"
                    || path == "/Users/test/Virtual Machines/Veil/uefi-vars.fd"
                    || path == "/opt/homebrew/bin/swtpm"
            },
            secureVarsTemplatePaths: [
                "/Users/test/Library/Application Support/Veil/Firmware/edk2-arm-secure-vars.fd"
            ]
        )

        #expect(plan.firmwarePath == "/opt/homebrew/share/qemu/edk2-aarch64-code.fd")
        #expect(plan.firmwareVarsTemplatePath == "/Users/test/Library/Application Support/Veil/Firmware/edk2-arm-secure-vars.fd")
        #expect(plan.isSecureBootFirmwareAvailable == false)
        #expect(plan.warnings.isEmpty)
    }

    @Test("local QEMU plan factory uses secure code and vars as a pair")
    func localQEMUPlanFactoryUsesSecureCodeAndVarsAsPair() throws {
        var profile = VMProfile.defaultWindows11Arm(createdAt: Date(timeIntervalSince1970: 1_782_752_400))
        profile.installerMediaPath = "/Users/test/Downloads/Win11_25H2_Korean_Arm64_v2.iso"
        profile.virtualDiskPath = "/Users/test/Virtual Machines/Veil/Windows 11 Arm.img"
        profile.sharedFolderPath = "/Users/test/Veil Shared"

        let plan = try LocalQEMUWindowsBootPlanFactory.makePlan(
            for: profile,
            architecture: "arm64",
            minimumOSSupported: true,
            providerProbe: VMRuntimeProviderProbe(
                environment: [:],
                fileExists: { $0 == "/opt/homebrew/bin/qemu-system-aarch64" },
                executableVersion: { _ in "QEMU emulator version 11.0.2" }
            ),
            fileExists: { path in
                path == "/opt/homebrew/share/qemu/edk2-aarch64-secure-code.fd"
                    || path == "/opt/homebrew/share/qemu/edk2-aarch64-code.fd"
                    || path == "/Users/test/Library/Application Support/Veil/Firmware/edk2-arm-secure-vars.fd"
                    || path == "/Users/test/Virtual Machines/Veil/uefi-vars.fd"
                    || path == "/opt/homebrew/bin/swtpm"
            },
            secureVarsTemplatePaths: [
                "/Users/test/Library/Application Support/Veil/Firmware/edk2-arm-secure-vars.fd"
            ]
        )

        #expect(plan.firmwarePath == "/opt/homebrew/share/qemu/edk2-aarch64-secure-code.fd")
        #expect(plan.firmwareVarsTemplatePath == "/Users/test/Library/Application Support/Veil/Firmware/edk2-arm-secure-vars.fd")
        #expect(plan.isSecureBootFirmwareAvailable)
        #expect(plan.arguments.containsSequence(["-drive", "if=pflash,format=raw,readonly=on,file=/opt/homebrew/share/qemu/edk2-aarch64-secure-code.fd"]))
    }

    @Test("local QEMU plan factory handles empty firmware vars candidate lists")
    func localQEMUPlanFactoryHandlesEmptyFirmwareVarsCandidateLists() throws {
        var profile = VMProfile.defaultWindows11Arm(createdAt: Date(timeIntervalSince1970: 1_782_752_400))
        profile.installerMediaPath = "/Users/test/Downloads/Win11_25H2_Korean_Arm64_v2.iso"
        profile.virtualDiskPath = "/Users/test/Virtual Machines/Veil/Windows 11 Arm.img"
        profile.sharedFolderPath = "/Users/test/Veil Shared"

        let plan = try LocalQEMUWindowsBootPlanFactory.makePlan(
            for: profile,
            architecture: "arm64",
            minimumOSSupported: true,
            providerProbe: VMRuntimeProviderProbe(
                environment: [:],
                fileExists: { $0 == "/opt/homebrew/bin/qemu-system-aarch64" },
                executableVersion: { _ in "QEMU emulator version 11.0.2" }
            ),
            fileExists: { path in
                path == "/opt/homebrew/share/qemu/edk2-aarch64-code.fd"
                    || path == "/Users/test/Virtual Machines/Veil/uefi-vars.fd"
                    || path == "/opt/homebrew/bin/swtpm"
            },
            secureVarsTemplatePaths: [],
            firmwareVarsTemplatePaths: []
        )

        #expect(plan.firmwareVarsTemplatePath == "/opt/homebrew/share/qemu/edk2-arm-vars.fd")
        #expect(plan.isFirmwareVarsTemplateAvailable == false)
        #expect(plan.isSecureBootFirmwareAvailable == false)
    }

    @Test("doctor warns when secure boot vars are available but not live verified")
    func doctorWarnsWhenSecureBootVarsAreAvailableButNotLiveVerified() throws {
        var profile = VMProfile.defaultWindows11Arm(createdAt: Date(timeIntervalSince1970: 1_782_752_400))
        profile.installerMediaPath = "/Users/test/Downloads/Win11_25H2_Korean_Arm64_v2.iso"
        profile.virtualDiskPath = "/Users/test/Virtual Machines/Veil/Windows 11 Arm.img"
        profile.sharedFolderPath = "/Users/test/Veil Shared"

        let planner = QEMUWindowsBootPlanner(
            executablePath: "/opt/homebrew/bin/qemu-system-aarch64",
            isExecutableAvailable: true,
            firmwarePath: "/opt/homebrew/share/qemu/edk2-aarch64-secure-code.fd",
            isFirmwareAvailable: true,
            firmwareVarsTemplatePath: "/Users/test/Library/Application Support/Veil/Firmware/edk2-arm-secure-vars.fd",
            isFirmwareVarsTemplateAvailable: true,
            firmwareVarsPath: "/Users/test/Virtual Machines/Veil/uefi-vars.fd",
            isSecureBootFirmwareAvailable: true,
            tpmEmulatorPath: "/opt/homebrew/bin/swtpm",
            isTPMEmulatorAvailable: true,
            tpmStateDirectoryPath: "/Users/test/Virtual Machines/Veil/tpm"
        )
        let plan = try planner.makePlan(for: profile)
        let doctor = QEMUWindowsReadinessDoctor(
            fileExists: { path in
                path == "/Users/test/Downloads/Win11_25H2_Korean_Arm64_v2.iso"
                    || path == "/Users/test/Veil Shared/VeilAutoInstall.iso"
                    || path == "/Users/test/Virtual Machines/Veil/Windows 11 Arm.img"
                    || path == "/opt/homebrew/bin/qemu-system-aarch64"
                    || path == "/opt/homebrew/share/qemu/edk2-aarch64-secure-code.fd"
                    || path == "/Users/test/Library/Application Support/Veil/Firmware/edk2-arm-secure-vars.fd"
                    || path == "/Users/test/Virtual Machines/Veil/uefi-vars.fd"
                    || path == "/opt/homebrew/bin/swtpm"
                    || path == "/Users/test/Virtual Machines/Veil/tpm"
            }
        )

        let report = doctor.makeReport(profile: profile, plan: plan)
        let secureBootCheck = try #require(report.checks.first { $0.id == "secure-boot" })

        #expect(report.overallState == .ready)
        #expect(secureBootCheck.state == .warning)
        #expect(secureBootCheck.detail == "AArch64 EDK2 secure variable template is available, but Secure Boot is not proven until a live Windows setup smoke passes the requirement check.")
    }

    @Test("doctor warns when secure vars are available without secure code")
    func doctorWarnsWhenSecureVarsAreAvailableWithoutSecureCode() throws {
        var profile = VMProfile.defaultWindows11Arm(createdAt: Date(timeIntervalSince1970: 1_782_752_400))
        profile.installerMediaPath = "/Users/test/Downloads/Win11_25H2_Korean_Arm64_v2.iso"
        profile.virtualDiskPath = "/Users/test/Virtual Machines/Veil/Windows 11 Arm.img"
        profile.sharedFolderPath = "/Users/test/Veil Shared"

        let planner = QEMUWindowsBootPlanner(
            executablePath: "/opt/homebrew/bin/qemu-system-aarch64",
            isExecutableAvailable: true,
            firmwarePath: "/opt/homebrew/share/qemu/edk2-aarch64-code.fd",
            isFirmwareAvailable: true,
            firmwareVarsTemplatePath: "/Users/test/Library/Application Support/Veil/Firmware/edk2-arm-secure-vars.fd",
            isFirmwareVarsTemplateAvailable: true,
            firmwareVarsPath: "/Users/test/Virtual Machines/Veil/uefi-vars.fd",
            isSecureBootFirmwareAvailable: false,
            tpmEmulatorPath: "/opt/homebrew/bin/swtpm",
            isTPMEmulatorAvailable: true,
            tpmStateDirectoryPath: "/Users/test/Virtual Machines/Veil/tpm"
        )
        let plan = try planner.makePlan(for: profile)
        let doctor = QEMUWindowsReadinessDoctor(
            fileExists: { path in
                path == "/Users/test/Downloads/Win11_25H2_Korean_Arm64_v2.iso"
                    || path == "/Users/test/Veil Shared/VeilAutoInstall.iso"
                    || path == "/Users/test/Virtual Machines/Veil/Windows 11 Arm.img"
                    || path == "/opt/homebrew/bin/qemu-system-aarch64"
                    || path == "/opt/homebrew/share/qemu/edk2-aarch64-code.fd"
                    || path == "/Users/test/Library/Application Support/Veil/Firmware/edk2-arm-secure-vars.fd"
                    || path == "/Users/test/Virtual Machines/Veil/uefi-vars.fd"
                    || path == "/opt/homebrew/bin/swtpm"
                    || path == "/Users/test/Virtual Machines/Veil/tpm"
            }
        )

        let report = doctor.makeReport(profile: profile, plan: plan)
        let secureBootCheck = try #require(report.checks.first { $0.id == "secure-boot" })

        #expect(report.overallState == .ready)
        #expect(secureBootCheck.state == .warning)
        #expect(secureBootCheck.detail == "AArch64 EDK2 secure variable template is available, but matching edk2-aarch64-secure-code.fd is missing.")
        #expect(report.nextActions.contains("Provide edk2-aarch64-secure-code.fd alongside edk2-arm-secure-vars.fd before rerunning Windows Setup smoke."))
    }

    @Test("doctor blocks when UEFI vars store is missing")
    func doctorBlocksWhenUEFIVarsStoreIsMissing() throws {
        var profile = VMProfile.defaultWindows11Arm(createdAt: Date(timeIntervalSince1970: 1_782_752_400))
        profile.installerMediaPath = "/Users/test/Downloads/Win11_25H2_Korean_Arm64_v2.iso"
        profile.virtualDiskPath = "/Users/test/Virtual Machines/Veil/Windows 11 Arm.img"
        profile.sharedFolderPath = "/Users/test/Veil Shared"

        let planner = QEMUWindowsBootPlanner(
            executablePath: "/opt/homebrew/bin/qemu-system-aarch64",
            isExecutableAvailable: true,
            firmwarePath: "/opt/homebrew/share/qemu/edk2-aarch64-code.fd",
            isFirmwareAvailable: true,
            firmwareVarsTemplatePath: "/opt/homebrew/share/qemu/edk2-arm-vars.fd",
            isFirmwareVarsTemplateAvailable: true,
            firmwareVarsPath: "/Users/test/Virtual Machines/Veil/uefi-vars.fd",
            isSecureBootFirmwareAvailable: false,
            tpmEmulatorPath: "/opt/homebrew/bin/swtpm",
            isTPMEmulatorAvailable: true,
            tpmStateDirectoryPath: "/Users/test/Virtual Machines/Veil/tpm"
        )
        let plan = try planner.makePlan(for: profile)
        let doctor = QEMUWindowsReadinessDoctor(
            fileExists: { path in
                path == "/Users/test/Downloads/Win11_25H2_Korean_Arm64_v2.iso"
                    || path == "/Users/test/Veil Shared/VeilAutoInstall.iso"
                    || path == "/Users/test/Virtual Machines/Veil/Windows 11 Arm.img"
                    || path == "/opt/homebrew/bin/qemu-system-aarch64"
                    || path == "/opt/homebrew/share/qemu/edk2-aarch64-code.fd"
                    || path == "/opt/homebrew/share/qemu/edk2-arm-vars.fd"
                    || path == "/opt/homebrew/bin/swtpm"
                    || path == "/Users/test/Virtual Machines/Veil/tpm"
            }
        )

        let report = doctor.makeReport(profile: profile, plan: plan)
        let firmwareCheck = try #require(report.checks.first { $0.id == "uefi-firmware" })

        #expect(report.overallState == .blocked)
        #expect(firmwareCheck.state == .blocked)
        #expect(firmwareCheck.detail == "Writable Arm UEFI variable store is missing at /Users/test/Virtual Machines/Veil/uefi-vars.fd.")
        #expect(report.nextActions.contains("Run veil-vmctl prepare --installer /path/to/Windows.iso to create Veil's writable UEFI variable store."))
    }

    @Test("doctor blocks when QEMU executable is missing")
    func doctorBlocksWhenQEMUExecutableIsMissing() throws {
        var profile = VMProfile.defaultWindows11Arm(createdAt: Date(timeIntervalSince1970: 1_782_752_400))
        profile.installerMediaPath = "/Users/test/Downloads/Win11_25H2_Korean_Arm64_v2.iso"
        profile.virtualDiskPath = "/Users/test/Virtual Machines/Veil/Windows 11 Arm.img"
        profile.sharedFolderPath = "/Users/test/Veil Shared"

        let planner = QEMUWindowsBootPlanner(
            executablePath: "/opt/homebrew/bin/qemu-system-aarch64",
            isExecutableAvailable: false,
            firmwarePath: "/opt/homebrew/share/qemu/edk2-aarch64-code.fd",
            isFirmwareAvailable: true
        )
        let plan = try planner.makePlan(for: profile)
        let doctor = QEMUWindowsReadinessDoctor(
            fileExists: { path in
                path == "/Users/test/Downloads/Win11_25H2_Korean_Arm64_v2.iso"
                    || path == "/Users/test/Veil Shared/VeilAutoInstall.iso"
                    || path == "/Users/test/Virtual Machines/Veil/Windows 11 Arm.img"
                    || path == "/opt/homebrew/share/qemu/edk2-aarch64-code.fd"
            }
        )

        let report = doctor.makeReport(profile: profile, plan: plan)
        let qemuCheck = try #require(report.checks.first { $0.id == "qemu-executable" })

        #expect(report.overallState == .blocked)
        #expect(qemuCheck.state == .blocked)
        #expect(qemuCheck.detail == "qemu-system-aarch64 is not available at /opt/homebrew/bin/qemu-system-aarch64.")
        #expect(report.nextActions.contains("Install QEMU with Homebrew or set VEIL_QEMU_SYSTEM_AARCH64 to the local qemu-system-aarch64 path."))
    }

    @Test("doctor blocks when TPM emulator is missing")
    func doctorBlocksWhenTPMEmulatorIsMissing() throws {
        var profile = VMProfile.defaultWindows11Arm(createdAt: Date(timeIntervalSince1970: 1_782_752_400))
        profile.installerMediaPath = "/Users/test/Downloads/Win11_25H2_Korean_Arm64_v2.iso"
        profile.virtualDiskPath = "/Users/test/Virtual Machines/Veil/Windows 11 Arm.img"
        profile.sharedFolderPath = "/Users/test/Veil Shared"

        let planner = QEMUWindowsBootPlanner(
            executablePath: "/opt/homebrew/bin/qemu-system-aarch64",
            isExecutableAvailable: true,
            firmwarePath: "/opt/homebrew/share/qemu/edk2-aarch64-code.fd",
            isFirmwareAvailable: true,
            tpmEmulatorPath: "/opt/homebrew/bin/swtpm",
            isTPMEmulatorAvailable: false,
            tpmStateDirectoryPath: "/Users/test/Virtual Machines/Veil/tpm"
        )
        let plan = try planner.makePlan(for: profile)
        let doctor = QEMUWindowsReadinessDoctor(
            fileExists: { path in
                path == "/Users/test/Downloads/Win11_25H2_Korean_Arm64_v2.iso"
                    || path == "/Users/test/Veil Shared/VeilAutoInstall.iso"
                    || path == "/Users/test/Virtual Machines/Veil/Windows 11 Arm.img"
                    || path == "/opt/homebrew/bin/qemu-system-aarch64"
                    || path == "/opt/homebrew/share/qemu/edk2-aarch64-code.fd"
            }
        )

        let report = doctor.makeReport(profile: profile, plan: plan)
        let tpmCheck = try #require(report.checks.first { $0.id == "tpm-emulator" })

        #expect(report.overallState == .blocked)
        #expect(tpmCheck.state == .blocked)
        #expect(tpmCheck.detail == "swtpm is not available at /opt/homebrew/bin/swtpm.")
        #expect(report.nextActions.contains("Install swtpm locally so Veil can attach a TPM 2.0 emulator for Windows 11 setup."))
    }

    @Test("doctor blocks when UEFI firmware is missing")
    func doctorBlocksWhenFirmwareIsMissing() throws {
        var profile = VMProfile.defaultWindows11Arm(createdAt: Date(timeIntervalSince1970: 1_782_752_400))
        profile.installerMediaPath = "/Users/test/Downloads/Win11_25H2_Korean_Arm64_v2.iso"
        profile.virtualDiskPath = "/Users/test/Virtual Machines/Veil/Windows 11 Arm.img"
        profile.sharedFolderPath = "/Users/test/Veil Shared"

        let planner = QEMUWindowsBootPlanner(
            executablePath: "/opt/homebrew/bin/qemu-system-aarch64",
            isExecutableAvailable: true,
            firmwarePath: "/opt/homebrew/share/qemu/edk2-aarch64-code.fd",
            isFirmwareAvailable: false
        )
        let plan = try planner.makePlan(for: profile)
        let doctor = QEMUWindowsReadinessDoctor(
            fileExists: { path in
                path == "/Users/test/Downloads/Win11_25H2_Korean_Arm64_v2.iso"
                    || path == "/Users/test/Veil Shared/VeilAutoInstall.iso"
                    || path == "/Users/test/Virtual Machines/Veil/Windows 11 Arm.img"
                    || path == "/opt/homebrew/bin/qemu-system-aarch64"
            }
        )

        let report = doctor.makeReport(profile: profile, plan: plan)
        let firmwareCheck = try #require(report.checks.first { $0.id == "uefi-firmware" })

        #expect(plan.warnings.contains("QEMU Arm UEFI firmware is not available at /opt/homebrew/share/qemu/edk2-aarch64-code.fd. Install QEMU from Homebrew or point Veil at an edk2-aarch64-code.fd file."))
        #expect(report.overallState == .blocked)
        #expect(firmwareCheck.state == .blocked)
        #expect(firmwareCheck.detail == "Arm UEFI firmware is not available at /opt/homebrew/share/qemu/edk2-aarch64-code.fd.")
        #expect(report.nextActions.contains("Install QEMU from Homebrew or point Veil at edk2-aarch64-code.fd and edk2-arm-vars.fd before launching Windows setup."))
    }

    @Test("smoke analyzer reports UEFI shell fallback with boot timeout evidence")
    func smokeAnalyzerReportsUEFIShellFallback() {
        let serialOutput = """
        BdsDxe: starting Boot0001 "UEFI QEMU QEMU USB HARDDRIVE 1-0000:00:01.0-1"
        Error: Image at 001BC344000 start failed: Time out
        BdsDxe: failed to start Boot0001 "UEFI QEMU QEMU USB HARDDRIVE 1-0000:00:01.0-1": Time out
        UEFI Interactive Shell v2.2
        Shell>
        """

        let report = QEMUWindowsBootSmokeAnalyzer.makeReport(
            durationSeconds: 45,
            processOutput: "",
            serialOutput: serialOutput,
            didRemainRunningUntilTimeout: true,
            serialLogPath: "/tmp/serial.log",
            processLogPath: "/tmp/process.log",
            consoleScreenshotPath: "/tmp/qemu-console.png"
        )

        #expect(report.outcome == .uefiShell)
        #expect(report.evidence.contains("boot-image-timeout"))
        #expect(report.evidence.contains("uefi-shell"))
        #expect(report.consoleScreenshotPath == "/tmp/qemu-console.png")
        #expect(report.detail == "QEMU reached Arm UEFI, but Windows Setup did not start and firmware fell back to the EDK II shell.")
        #expect(report.nextActions.contains("Confirm the installer ISO is attached as the first bootable USB/CD-ROM device and contains efi/boot/bootaa64.efi."))
        #expect(report.nextActions.contains("Open the console screenshot and serial log together to compare the visible firmware state with the boot text."))
    }

    @Test("smoke analyzer reports argument failures before firmware")
    func smokeAnalyzerReportsArgumentFailure() {
        let report = QEMUWindowsBootSmokeAnalyzer.makeReport(
            durationSeconds: 5,
            processOutput: "qemu-system-aarch64: -accel hvf: Addressing limited to 32 bits",
            serialOutput: "",
            didRemainRunningUntilTimeout: false,
            serialLogPath: "/tmp/serial.log",
            processLogPath: "/tmp/process.log",
            consoleScreenshotPath: "/tmp/qemu-console.png"
        )

        #expect(report.outcome == .argumentFailure)
        #expect(report.evidence == ["qemu-argument-error"])
        #expect(report.consoleScreenshotPath == "/tmp/qemu-console.png")
        #expect(report.nextActions.contains("Open the process log and fix the rejected QEMU argument or local resource path before retrying."))
    }

    @Test("smoke analyzer ignores expected timeout termination text")
    func smokeAnalyzerIgnoresExpectedTerminationText() {
        let report = QEMUWindowsBootSmokeAnalyzer.makeReport(
            durationSeconds: 25,
            processOutput: "qemu-system-aarch64: terminating on signal 15 from pid 4766",
            serialOutput: "Error: Image at 0027C344000 start failed: Time out\nUEFI Interactive Shell v2.2\nShell>",
            didRemainRunningUntilTimeout: true,
            serialLogPath: "/tmp/serial.log",
            processLogPath: "/tmp/process.log",
            consoleScreenshotPath: "/tmp/qemu-console.png"
        )

        #expect(report.outcome == .uefiShell)
        #expect(report.evidence == ["boot-image-timeout", "uefi-shell"])
    }

    @Test("smoke analyzer reports boot prompt key evidence")
    func smokeAnalyzerReportsBootPromptKeyEvidence() {
        let report = QEMUWindowsBootSmokeAnalyzer.makeReport(
            durationSeconds: 25,
            processOutput: "qemu-system-aarch64: terminating on signal 15 from pid 4766",
            serialOutput: "Error: Image at 0027C344000 start failed: Time out\nUEFI Interactive Shell v2.2\nShell>",
            didRemainRunningUntilTimeout: true,
            serialLogPath: "/tmp/serial.log",
            processLogPath: "/tmp/process.log",
            consoleScreenshotPath: "/tmp/qemu-console.png",
            runEvidence: ["boot-prompt-key-sent"]
        )

        #expect(report.outcome == .uefiShell)
        #expect(report.evidence == ["boot-prompt-key-sent", "boot-image-timeout", "uefi-shell"])
        #expect(report.nextActions.contains("The smoke run already sent boot prompt key input; inspect the console screenshot before changing the device recipe."))
    }

    @Test("smoke analyzer records TPM evidence from firmware output")
    func smokeAnalyzerRecordsTPMEvidence() {
        let report = QEMUWindowsBootSmokeAnalyzer.makeReport(
            durationSeconds: 120,
            processOutput: "",
            serialOutput: "SyncPcrAllocationsAndPcrMask!\nTpm2GetCapabilityPcrs - 00000004\nalg - B",
            didRemainRunningUntilTimeout: true,
            serialLogPath: "/tmp/serial.log",
            processLogPath: "/tmp/process.log",
            consoleScreenshotPath: "/tmp/qemu-console.png",
            runEvidence: ["boot-prompt-key-sent"]
        )

        #expect(report.outcome == .runningNoDecision)
        #expect(report.evidence.contains("tpm2-detected"))
    }

    @Test("smoke planner converts the interactive plan into a headless bounded smoke run")
    func smokePlannerBuildsHeadlessArguments() throws {
        var profile = VMProfile.defaultWindows11Arm(createdAt: Date(timeIntervalSince1970: 1_782_752_400))
        profile.installerMediaPath = "/Users/test/Downloads/Win11_25H2_Korean_Arm64_v2.iso"
        profile.virtualDiskPath = "/Users/test/Virtual Machines/Veil/Windows 11 Arm.img"
        profile.sharedFolderPath = "/Users/test/Veil Shared"
        let plan = try QEMUWindowsBootPlanner(
            executablePath: "/opt/homebrew/bin/qemu-system-aarch64",
            isExecutableAvailable: true,
            firmwarePath: "/opt/homebrew/share/qemu/edk2-aarch64-code.fd",
            isFirmwareAvailable: true
        ).makePlan(for: profile)

        let arguments = QEMUWindowsBootSmokePlanner().makeArguments(
            from: plan,
            serialLogPath: "/tmp/veil-qemu-smoke.serial.log",
            monitorSocketPath: "/tmp/veil-qemu-smoke.sock"
        )

        #expect(arguments.contains("-snapshot"))
        #expect(arguments.containsSequence(["-display", "none"]))
        #expect(arguments.containsSequence(["-serial", "file:/tmp/veil-qemu-smoke.serial.log"]))
        #expect(arguments.containsSequence(["-monitor", "unix:/tmp/veil-qemu-smoke.sock,server,nowait"]))
        #expect(arguments.contains("driver=raw,file.driver=file,file.locking=off,file.filename=/Users/test/Virtual Machines/Veil/Windows 11 Arm.img,if=none,id=system"))
        #expect(!arguments.contains("cocoa"))
    }

    @Test("launch planner keeps visible display and attaches monitor without snapshot mode")
    func launchPlannerBuildsVisiblePersistentArguments() throws {
        var profile = VMProfile.defaultWindows11Arm(createdAt: Date(timeIntervalSince1970: 1_782_752_400))
        profile.installerMediaPath = "/Users/test/Downloads/Win11_25H2_Korean_Arm64_v2.iso"
        profile.virtualDiskPath = "/Users/test/Virtual Machines/Veil/Windows 11 Arm.img"
        profile.sharedFolderPath = "/Users/test/Veil Shared"
        let plan = try QEMUWindowsBootPlanner(
            executablePath: "/opt/homebrew/bin/qemu-system-aarch64",
            isExecutableAvailable: true,
            firmwarePath: "/opt/homebrew/share/qemu/edk2-aarch64-code.fd",
            isFirmwareAvailable: true
        ).makePlan(for: profile)

        let arguments = QEMUWindowsBootLaunchPlanner().makeArguments(
            from: plan,
            serialLogPath: "/tmp/veil-qemu-launch.serial.log",
            monitorSocketPath: "/tmp/veil-qemu-launch.sock"
        )

        #expect(!arguments.contains("-snapshot"))
        #expect(arguments.containsSequence(["-display", "cocoa"]))
        #expect(arguments.containsSequence(["-serial", "file:/tmp/veil-qemu-launch.serial.log"]))
        #expect(arguments.containsSequence(["-monitor", "unix:/tmp/veil-qemu-launch.sock,server,nowait"]))
        #expect(arguments.contains("driver=raw,file.driver=file,file.locking=off,file.filename=/Users/test/Virtual Machines/Veil/Windows 11 Arm.img,if=none,id=system"))
    }

    @Test("smoke boot prompt automation sends bounded key attempts")
    func smokeBootPromptAutomationSendsBoundedKeyAttempts() {
        var automation = QEMUWindowsBootPromptAutomation()
        let monitorSocketURL = URL(fileURLWithPath: "/tmp/veil-qemu-smoke.sock")
        var sentPaths: [String] = []
        var sendResults: [Bool] = []

        for elapsedSecond in [0, 1, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14] {
            let didSend = automation.tick(elapsedSeconds: elapsedSecond, monitorSocketURL: monitorSocketURL) { url in
                sentPaths.append(url.path)
                return true
            }
            sendResults.append(didSend)
        }

        #expect(sentPaths.count == 12)
        #expect(sentPaths.allSatisfy { $0 == monitorSocketURL.path })
        #expect(sendResults == [
            false,
            true,
            false,
            true,
            true,
            true,
            true,
            true,
            true,
            true,
            true,
            true,
            true,
            true,
            false,
            false
        ])
    }

    @Test("smoke boot prompt automation retries when the monitor socket is not ready")
    func smokeBootPromptAutomationRetriesWhenMonitorSocketIsNotReady() {
        var automation = QEMUWindowsBootPromptAutomation()
        let monitorSocketURL = URL(fileURLWithPath: "/tmp/veil-qemu-smoke.sock")
        var attempts = 0

        let firstAttempt = automation.tick(elapsedSeconds: 1, monitorSocketURL: monitorSocketURL) { _ in
            attempts += 1
            return false
        }
        let retryAttempt = automation.tick(elapsedSeconds: 1, monitorSocketURL: monitorSocketURL) { _ in
            attempts += 1
            return true
        }

        #expect(firstAttempt == false)
        #expect(retryAttempt == true)
        #expect(attempts == 2)
    }

    @Test("QEMU boot key sender reports a missing monitor socket")
    func qemuBootKeySenderReportsMissingMonitorSocket() {
        let missingSocketURL = URL(fileURLWithPath: "/tmp/veil-missing-\(UUID().uuidString).sock")

        #expect(QEMUVMRuntimeBooter.sendWindowsInstallerBootKey(monitorSocketURL: missingSocketURL) == false)
    }

    @Test("TPM emulator startup terminates with the QEMU connection")
    func tpmEmulatorStartupTerminatesWithQEMUConnection() throws {
        let directory = try temporaryDirectory()
        let swtpmURL = directory.appendingPathComponent("swtpm")
        let argumentsURL = directory.appendingPathComponent("swtpm-args.txt")
        let tpmStateURL = directory.appendingPathComponent("tpm", isDirectory: true)
        let script = """
        #!/bin/sh
        printf '%s\\n' "$@" > '\(argumentsURL.path)'
        exit 0
        """
        try Data(script.utf8).write(to: swtpmURL)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: swtpmURL.path)

        let plan = QEMUWindowsBootPlan(
            provider: "QEMU/HVF",
            executablePath: "/opt/homebrew/bin/qemu-system-aarch64",
            isExecutableAvailable: true,
            firmwarePath: "/opt/homebrew/share/qemu/edk2-aarch64-code.fd",
            isFirmwareAvailable: true,
            tpmEmulatorPath: swtpmURL.path,
            isTPMEmulatorAvailable: true,
            tpmStateDirectoryPath: tpmStateURL.path,
            automaticInstallMediaPath: nil,
            summary: "test",
            arguments: [],
            warnings: []
        )

        try QEMUVMRuntimeBooter.startTPMEmulatorIfNeeded(plan: plan)

        let arguments = try String(contentsOf: argumentsURL, encoding: .utf8)
            .split(separator: "\n")
            .map(String.init)
        #expect(FileManager.default.fileExists(atPath: tpmStateURL.path))
        #expect(arguments.containsSequence(["--ctrl", "type=unixio,path=\(tpmStateURL.path)/swtpm.sock,terminate"]))
        #expect(arguments.containsSequence(["--pid", "file=\(tpmStateURL.path)/swtpm.pid"]))
    }

    @Test("QEMU runtime booter starts the local console process")
    func qemuRuntimeBooterStartsLocalConsoleProcess() async throws {
        let directory = try temporaryDirectory()
        let installerURL = directory.appendingPathComponent("Windows.iso")
        let diskURL = directory.appendingPathComponent("Windows.img")
        let sharedFolderURL = directory.appendingPathComponent("Veil Shared", isDirectory: true)
        let autoInstallURL = sharedFolderURL.appendingPathComponent("VeilAutoInstall.iso")
        let qemuURL = directory.appendingPathComponent("qemu-system-aarch64")
        let firmwareURL = directory.appendingPathComponent("edk2-aarch64-code.fd")
        let firmwareVarsTemplateURL = directory.appendingPathComponent("edk2-arm-vars.fd")
        let firmwareVarsURL = directory.appendingPathComponent("uefi-vars.fd")
        let swtpmURL = directory.appendingPathComponent("swtpm")
        let tpmStateURL = directory.appendingPathComponent("tpm", isDirectory: true)
        try FileManager.default.createDirectory(at: sharedFolderURL, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: tpmStateURL, withIntermediateDirectories: true)
        try Data("installer".utf8).write(to: installerURL)
        try Data("disk".utf8).write(to: diskURL)
        try Data("auto".utf8).write(to: autoInstallURL)
        try Data("qemu".utf8).write(to: qemuURL)
        try Data("firmware".utf8).write(to: firmwareURL)
        try Data("vars-template".utf8).write(to: firmwareVarsTemplateURL)
        try Data("vars".utf8).write(to: firmwareVarsURL)
        try Data("swtpm".utf8).write(to: swtpmURL)

        var profile = VMProfile.defaultWindows11Arm(createdAt: Date(timeIntervalSince1970: 1_782_752_400))
        profile.installerMediaPath = installerURL.path
        profile.virtualDiskPath = diskURL.path
        profile.sharedFolderPath = sharedFolderURL.path

        let plan = try QEMUWindowsBootPlanner(
            executablePath: qemuURL.path,
            isExecutableAvailable: true,
            firmwarePath: firmwareURL.path,
            isFirmwareAvailable: true,
            firmwareVarsTemplatePath: firmwareVarsTemplateURL.path,
            isFirmwareVarsTemplateAvailable: true,
            firmwareVarsPath: firmwareVarsURL.path,
            isSecureBootFirmwareAvailable: false,
            tpmEmulatorPath: swtpmURL.path,
            isTPMEmulatorAvailable: true,
            tpmStateDirectoryPath: tpmStateURL.path
        ).makePlan(for: profile)
        final class Capture: @unchecked Sendable {
            var executablePath: String?
            var arguments: [String] = []
            var tpmPlan: QEMUWindowsBootPlan?
        }
        let capture = Capture()
        let booter = QEMUVMRuntimeBooter(
            diagnosticsDirectory: directory,
            planBuilder: { _ in plan },
            tpmEmulatorRunner: { plan in
                capture.tpmPlan = plan
            },
            processRunner: { process in
                capture.executablePath = process.executableURL?.path
                capture.arguments = process.arguments ?? []
            },
            frontmostRunner: {},
            bootKeySender: { _ in true }
        )

        let state = try await booter.start(profile: profile)

        #expect(state == .running)
        #expect(capture.tpmPlan?.tpmEmulatorPath == swtpmURL.path)
        #expect(capture.executablePath == qemuURL.path)
        #expect(capture.arguments.containsSequence(["-display", "cocoa"]))
        #expect(capture.arguments.contains("-monitor"))
        #expect(capture.arguments.contains { $0.hasPrefix("unix:") && $0.hasSuffix(",server,nowait") })
        #expect(capture.arguments.contains("driver=raw,file.driver=file,file.locking=off,file.filename=\(autoInstallURL.path),if=none,id=autounattend,media=cdrom,readonly=on"))

        let recordURL = directory
            .appendingPathComponent("QEMU Launch", isDirectory: true)
            .appendingPathComponent("qemu-launch-latest.json")
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let record = try decoder.decode(QEMULaunchRecord.self, from: Data(contentsOf: recordURL))
        #expect(record.kind == "qemuWindowsArmLaunch")
        #expect(record.provider == "QEMU/HVF")
        #expect(record.isServerBacked == false)
        #expect(record.executablePath == qemuURL.path)
        #expect(record.arguments.containsSequence(["-display", "cocoa"]))
        #expect(record.arguments.contains("driver=raw,file.driver=file,file.locking=off,file.filename=\(autoInstallURL.path),if=none,id=autounattend,media=cdrom,readonly=on"))
        #expect(record.processLogPath.hasSuffix(".log"))
        #expect(record.monitorSocketPath.contains("/tmp/vq-"))
        #expect(record.consoleScreenshotPath?.contains("qemu-console-") == true)
        #expect(record.consoleScreenshotPath?.hasSuffix(".png") == true)
    }
}

private extension [String] {
    func containsSequence(_ sequence: [String]) -> Bool {
        guard !sequence.isEmpty, count >= sequence.count else {
            return false
        }

        for startIndex in 0...(count - sequence.count) {
            if Array(self[startIndex..<(startIndex + sequence.count)]) == sequence {
                return true
            }
        }

        return false
    }
}

private func temporaryDirectory() throws -> URL {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    return directory
}
