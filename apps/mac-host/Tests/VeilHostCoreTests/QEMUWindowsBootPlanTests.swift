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
        profile.cpuCount = 8
        profile.memoryMB = 12_288

        let planner = QEMUWindowsBootPlanner(
            executablePath: "/opt/homebrew/bin/qemu-system-aarch64",
            isExecutableAvailable: true
        )

        let plan = try planner.makePlan(for: profile)

        #expect(plan.executablePath == "/opt/homebrew/bin/qemu-system-aarch64")
        #expect(plan.isExecutableAvailable)
        #expect(plan.arguments.containsSequence(["-machine", "virt,highmem=on"]))
        #expect(plan.arguments.containsSequence(["-accel", "hvf"]))
        #expect(plan.arguments.containsSequence(["-cpu", "host"]))
        #expect(plan.arguments.containsSequence(["-smp", "8"]))
        #expect(plan.arguments.containsSequence(["-m", "12288M"]))
        #expect(plan.arguments.contains("if=none,id=installer,media=cdrom,readonly=on,file=/Users/test/Downloads/Win11_25H2_Korean_Arm64_v2.iso"))
        #expect(plan.arguments.contains("if=none,id=system,format=raw,file=/Users/test/Virtual Machines/Veil/Windows 11 Arm.img"))
        #expect(plan.arguments.containsSequence(["-netdev", "user,id=net0"]))
        #expect(plan.arguments.containsSequence(["-device", "virtio-net-pci,netdev=net0"]))
        #expect(plan.arguments.containsSequence(["-display", "cocoa"]))
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
            isExecutableAvailable: true
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

        let planner = QEMUWindowsBootPlanner(
            executablePath: "/opt/homebrew/bin/qemu-system-aarch64",
            isExecutableAvailable: false
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

        let planner = QEMUWindowsBootPlanner(
            executablePath: "/opt/homebrew/bin/qemu-system-aarch64",
            isExecutableAvailable: true
        )
        let plan = try planner.makePlan(for: profile)
        let doctor = QEMUWindowsReadinessDoctor(
            fileExists: { path in
                path == "/Users/test/Downloads/Win11_25H2_Korean_Arm64_v2.iso"
                    || path == "/Users/test/Virtual Machines/Veil/Windows 11 Arm.img"
                    || path == "/opt/homebrew/bin/qemu-system-aarch64"
            }
        )

        let report = doctor.makeReport(profile: profile, plan: plan)

        #expect(report.overallState == .ready)
        #expect(report.isServerBacked == false)
        #expect(report.checks.map(\.id) == [
            "vm-profile",
            "installer-media",
            "system-disk",
            "qemu-executable",
            "hvf-plan"
        ])
        #expect(report.checks.allSatisfy { $0.state == .passed })
        #expect(report.nextActions == ["Run veil-vmctl qemu-plan --json to review the exact command before execution support lands."])
    }

    @Test("doctor blocks when QEMU executable is missing")
    func doctorBlocksWhenQEMUExecutableIsMissing() throws {
        var profile = VMProfile.defaultWindows11Arm(createdAt: Date(timeIntervalSince1970: 1_782_752_400))
        profile.installerMediaPath = "/Users/test/Downloads/Win11_25H2_Korean_Arm64_v2.iso"
        profile.virtualDiskPath = "/Users/test/Virtual Machines/Veil/Windows 11 Arm.img"

        let planner = QEMUWindowsBootPlanner(
            executablePath: "/opt/homebrew/bin/qemu-system-aarch64",
            isExecutableAvailable: false
        )
        let plan = try planner.makePlan(for: profile)
        let doctor = QEMUWindowsReadinessDoctor(
            fileExists: { path in
                path == "/Users/test/Downloads/Win11_25H2_Korean_Arm64_v2.iso"
                    || path == "/Users/test/Virtual Machines/Veil/Windows 11 Arm.img"
            }
        )

        let report = doctor.makeReport(profile: profile, plan: plan)
        let qemuCheck = try #require(report.checks.first { $0.id == "qemu-executable" })

        #expect(report.overallState == .blocked)
        #expect(qemuCheck.state == .blocked)
        #expect(qemuCheck.detail == "qemu-system-aarch64 is not available at /opt/homebrew/bin/qemu-system-aarch64.")
        #expect(report.nextActions.contains("Install QEMU with Homebrew or set VEIL_QEMU_SYSTEM_AARCH64 to the local qemu-system-aarch64 path."))
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
