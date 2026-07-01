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
            isFirmwareAvailable: true
        )

        let plan = try planner.makePlan(for: profile)

        #expect(plan.executablePath == "/opt/homebrew/bin/qemu-system-aarch64")
        #expect(plan.isExecutableAvailable)
        #expect(plan.firmwarePath == "/opt/homebrew/share/qemu/edk2-aarch64-code.fd")
        #expect(plan.isFirmwareAvailable)
        #expect(plan.arguments.containsSequence(["-machine", "virt,highmem=on"]))
        #expect(plan.arguments.containsSequence(["-accel", "hvf"]))
        #expect(plan.arguments.containsSequence(["-bios", "/opt/homebrew/share/qemu/edk2-aarch64-code.fd"]))
        #expect(plan.arguments.containsSequence(["-boot", "order=d"]))
        #expect(plan.arguments.containsSequence(["-cpu", "host"]))
        #expect(plan.arguments.containsSequence(["-smp", "8"]))
        #expect(plan.arguments.containsSequence(["-m", "12288M"]))
        #expect(plan.arguments.contains("driver=raw,file.driver=file,file.locking=off,file.filename=/Users/test/Downloads/Win11_25H2_Korean_Arm64_v2.iso,if=none,id=installer,media=cdrom,readonly=on"))
        #expect(plan.automaticInstallMediaPath == "/Users/test/Veil Shared/VeilAutoInstall.iso")
        #expect(plan.arguments.contains("driver=raw,file.driver=file,file.locking=off,file.filename=/Users/test/Veil Shared/VeilAutoInstall.iso,if=none,id=autounattend,media=cdrom,readonly=on"))
        #expect(plan.arguments.contains("if=none,id=system,format=raw,file=/Users/test/Virtual Machines/Veil/Windows 11 Arm.img"))
        #expect(plan.arguments.containsSequence(["-netdev", "user,id=net0"]))
        #expect(plan.arguments.containsSequence(["-device", "virtio-net-pci,netdev=net0"]))
        #expect(plan.arguments.containsSequence(["-display", "cocoa"]))
        #expect(plan.arguments.containsSequence(["-device", "qemu-xhci,id=usb0"]))
        #expect(plan.arguments.containsSequence(["-device", "usb-storage,drive=autounattend"]))
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
            isFirmwareAvailable: true
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
            isFirmwareAvailable: true
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

        #expect(report.overallState == .ready)
        #expect(report.isServerBacked == false)
        #expect(report.checks.map(\.id) == [
            "vm-profile",
            "installer-media",
            "automatic-install-media",
            "system-disk",
            "qemu-executable",
            "uefi-firmware",
            "hvf-plan"
        ])
        #expect(report.checks.allSatisfy { $0.state == .passed })
        #expect(report.nextActions == ["Run veil-vmctl qemu-start to launch the local QEMU/HVF Windows setup window."])
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
        #expect(report.nextActions.contains("Install QEMU from Homebrew or point Veil at edk2-aarch64-code.fd before launching Windows setup."))
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
            processLogPath: "/tmp/process.log"
        )

        #expect(report.outcome == .uefiShell)
        #expect(report.evidence.contains("boot-image-timeout"))
        #expect(report.evidence.contains("uefi-shell"))
        #expect(report.detail == "QEMU reached Arm UEFI, but Windows Setup did not start and firmware fell back to the EDK II shell.")
    }

    @Test("smoke analyzer reports argument failures before firmware")
    func smokeAnalyzerReportsArgumentFailure() {
        let report = QEMUWindowsBootSmokeAnalyzer.makeReport(
            durationSeconds: 5,
            processOutput: "qemu-system-aarch64: -accel hvf: Addressing limited to 32 bits",
            serialOutput: "",
            didRemainRunningUntilTimeout: false,
            serialLogPath: "/tmp/serial.log",
            processLogPath: "/tmp/process.log"
        )

        #expect(report.outcome == .argumentFailure)
        #expect(report.evidence == ["qemu-argument-error"])
    }

    @Test("smoke analyzer ignores expected timeout termination text")
    func smokeAnalyzerIgnoresExpectedTerminationText() {
        let report = QEMUWindowsBootSmokeAnalyzer.makeReport(
            durationSeconds: 25,
            processOutput: "qemu-system-aarch64: terminating on signal 15 from pid 4766",
            serialOutput: "Error: Image at 0027C344000 start failed: Time out\nUEFI Interactive Shell v2.2\nShell>",
            didRemainRunningUntilTimeout: true,
            serialLogPath: "/tmp/serial.log",
            processLogPath: "/tmp/process.log"
        )

        #expect(report.outcome == .uefiShell)
        #expect(report.evidence == ["boot-image-timeout", "uefi-shell"])
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
            serialLogPath: "/tmp/veil-qemu-smoke.serial.log"
        )

        #expect(arguments.contains("-snapshot"))
        #expect(arguments.containsSequence(["-display", "none"]))
        #expect(arguments.containsSequence(["-serial", "file:/tmp/veil-qemu-smoke.serial.log"]))
        #expect(arguments.containsSequence(["-monitor", "none"]))
        #expect(arguments.contains("driver=raw,file.driver=file,file.locking=off,file.filename=/Users/test/Virtual Machines/Veil/Windows 11 Arm.img,if=none,id=system"))
        #expect(!arguments.contains("cocoa"))
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
