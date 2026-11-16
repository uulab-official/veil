import Foundation
import Testing

@testable import VeilHostCore

@Suite("Generic guest boot plans")
struct QEMUGuestBootPlanTests {
    private let vmDirectory = URL(fileURLWithPath: "/VMs/vm_test", isDirectory: true)
    private let firmware = QEMUGuestFirmware(
        codePath: "/qemu/share/qemu/edk2-aarch64-code.fd",
        varsTemplatePath: "/qemu/share/qemu/edk2-arm-vars.fd",
        isAvailable: true
    )

    private func guest(_ guestOS: VMGuestOS, iso: String? = "/ISO/installer.iso") -> VMProfile {
        .newGuest(guestOS, name: "Test", installerMediaPath: iso, directory: vmDirectory, createdAt: Date(timeIntervalSince1970: 0), id: "vm_test")
    }

    private func value(after flag: String, matching prefix: String, in arguments: [String]) -> String? {
        zip(arguments, arguments.dropFirst())
            .first { $0.0 == flag && $0.1.hasPrefix(prefix) }?
            .1
    }

    @Test("existing profiles keep decoding as Windows")
    func existingProfilesStayWindows() throws {
        let windows = VMProfile.defaultWindows11Arm(createdAt: Date(timeIntervalSince1970: 0))
        #expect(windows.os == "windows-arm64")
        #expect(windows.guestOS == .windows11Arm)

        var unknown = windows
        unknown.os = "something-else"
        #expect(unknown.guestOS == .windows11Arm)
    }

    @Test("new guest profiles carry their kind, folder, and defaults")
    func newGuestProfile() {
        let profile = guest(.x86_64)
        #expect(profile.os == "x86_64")
        #expect(profile.guestOS == .x86_64)
        #expect(profile.virtualDiskPath == "/VMs/vm_test/disk.img")
        #expect(profile.cpuCount == 2)
        #expect(profile.memoryMB == 2_048)
        #expect(profile.autoStart == false)
        #expect(VMProfile.newGuestID().count == 15)
    }

    @Test("Windows profiles are refused by the generic planner")
    func windowsIsRefused() {
        let planner = QEMUGuestBootPlanner(executablePath: "/qemu/bin/qemu-system-aarch64", isExecutableAvailable: true, firmware: firmware)
        #expect(throws: QEMUGuestBootPlanError.windowsUsesWindowsPlanner) {
            try planner.makePlan(for: VMProfile.defaultWindows11Arm())
        }
    }

    @Test("Linux Arm64 boots on HVF with virtio devices and no Windows extras")
    func linuxArm64Plan() throws {
        let planner = QEMUGuestBootPlanner(executablePath: "/qemu/bin/qemu-system-aarch64", isExecutableAvailable: true, firmware: firmware)
        let plan = try planner.makePlan(for: guest(.linuxArm64))
        let arguments = plan.arguments

        #expect(plan.accelerator == "hvf")
        #expect(plan.isLaunchable)
        #expect(plan.warnings.isEmpty)
        #expect(value(after: "-machine", matching: "virt", in: arguments) == "virt,highmem=on")
        #expect(value(after: "-accel", matching: "", in: arguments) == "hvf")
        #expect(arguments.contains("virtio-blk-pci,drive=system,bootindex=0"))
        #expect(arguments.contains("virtio-net-pci,netdev=net0"))
        #expect(arguments.contains("virtio-gpu-pci"))
        #expect(arguments.contains("scsi-cd,bus=scsi0.0,drive=installer,bootindex=1"))
        #expect(value(after: "-drive", matching: "if=pflash,format=raw,readonly=on", in: arguments)?.hasSuffix("edk2-aarch64-code.fd") == true)
        #expect(plan.firmwareVarsPath == "/VMs/vm_test/uefi-vars.fd")

        // Nothing from the Windows path: no agent forward, answer file, TPM, or installer AHCI copy.
        let joined = arguments.joined(separator: " ")
        #expect(!joined.contains("hostfwd"))
        #expect(!joined.contains("autounattend"))
        #expect(!joined.contains("tpm"))
        #expect(!joined.contains("ahci"))
    }

    @Test("an installed guest without an ISO boots only its disk")
    func noInstallerMedia() throws {
        let planner = QEMUGuestBootPlanner(executablePath: "/qemu/bin/qemu-system-aarch64", isExecutableAvailable: true, firmware: firmware)
        let plan = try planner.makePlan(for: guest(.linuxArm64, iso: nil))
        #expect(!plan.arguments.contains { $0.contains("installer") })
    }

    @Test("TPM is added only when requested and swtpm exists")
    func optionalTPM() throws {
        let withTPM = QEMUGuestBootPlanner(
            executablePath: "/qemu/bin/qemu-system-aarch64",
            isExecutableAvailable: true,
            firmware: firmware,
            tpmEmulatorPath: "/qemu/bin/swtpm",
            options: QEMUGuestBootOptions(tpm: true)
        )
        let plan = try withTPM.makePlan(for: guest(.linuxArm64))
        #expect(plan.arguments.contains("tpm-tis-device,tpmdev=tpm0,ppi=off"))
        #expect(plan.tpmStateDirectoryPath == "/VMs/vm_test/tpm")
        #expect(plan.isLaunchable)

        let missingSwtpm = QEMUGuestBootPlanner(
            executablePath: "/qemu/bin/qemu-system-aarch64",
            isExecutableAvailable: true,
            firmware: firmware,
            options: QEMUGuestBootOptions(tpm: true)
        )
        let blocked = try missingSwtpm.makePlan(for: guest(.linuxArm64))
        #expect(!blocked.isLaunchable)
        #expect(!blocked.arguments.contains { $0.contains("tpm") })
    }

    @Test("x86_64 uses TCG on q35 with OVMF and warns about speed")
    func x86Plan() throws {
        let ovmf = QEMUGuestFirmware(codePath: "/q/edk2-x86_64-code.fd", varsTemplatePath: "/q/edk2-i386-vars.fd", isAvailable: true)
        let planner = QEMUGuestBootPlanner(
            executablePath: "/qemu/bin/qemu-system-x86_64",
            isExecutableAvailable: true,
            firmware: ovmf,
            options: QEMUGuestBootOptions(secureBoot: true)
        )
        let plan = try planner.makePlan(for: guest(.x86_64))
        let arguments = plan.arguments

        #expect(plan.accelerator == "tcg")
        #expect(value(after: "-machine", matching: "", in: arguments) == "q35")
        #expect(value(after: "-accel", matching: "", in: arguments)?.hasPrefix("tcg,thread=multi") == true)
        #expect(!arguments.contains("hvf"))
        #expect(arguments.contains("VGA"))
        #expect(plan.warnings.contains(QEMUGuestBootPlanner.emulationPerformanceWarning))
        #expect(plan.warnings.contains { $0.contains("Secure Boot is not offered") })
    }

    @Test("missing executable or firmware blocks launch with a reason")
    func missingPieces() throws {
        let planner = QEMUGuestBootPlanner(
            executablePath: "/nowhere/qemu-system-x86_64",
            isExecutableAvailable: false,
            firmware: QEMUGuestFirmware(codePath: "/nowhere/a.fd", varsTemplatePath: "/nowhere/b.fd", isAvailable: false)
        )
        let plan = try planner.makePlan(for: guest(.x86_64))
        #expect(!plan.isLaunchable)
        #expect(plan.warnings.contains { $0.contains("qemu-system-x86_64 is not available") })
        #expect(plan.warnings.contains { $0.contains("UEFI firmware") })
    }

    @Test("the local factory prefers the bundled runtime and picks firmware by guest kind")
    func localFactoryResolution() throws {
        let bundled = URL(fileURLWithPath: "/App/Runtime", isDirectory: true)
        let present: Set<String> = [
            "/App/Runtime/bin/qemu-system-aarch64",
            "/App/Runtime/bin/qemu-system-x86_64",
            "/App/Runtime/share/qemu/edk2-aarch64-code.fd",
            "/App/Runtime/share/qemu/edk2-arm-vars.fd",
            "/App/Runtime/share/qemu/edk2-x86_64-code.fd",
            "/App/Runtime/share/qemu/edk2-i386-vars.fd",
            "/Home/Library/Application Support/Veil/Firmware/edk2-aarch64-secure-code.fd",
            "/Home/Library/Application Support/Veil/Firmware/edk2-arm-secure-vars.fd"
        ]
        let fileExists: @Sendable (String) -> Bool = { present.contains($0) }
        let home = URL(fileURLWithPath: "/Home", isDirectory: true)

        let arm = try LocalQEMUGuestBootPlanFactory.makePlan(
            for: guest(.linuxArm64), environment: [:], homeDirectory: home, bundledRuntimeDirectory: bundled, fileExists: fileExists
        )
        #expect(arm.executablePath == "/App/Runtime/bin/qemu-system-aarch64")
        #expect(arm.firmwareCodePath == "/App/Runtime/share/qemu/edk2-aarch64-code.fd")

        let secure = try LocalQEMUGuestBootPlanFactory.makePlan(
            for: guest(.linuxArm64), options: QEMUGuestBootOptions(secureBoot: true),
            environment: [:], homeDirectory: home, bundledRuntimeDirectory: bundled, fileExists: fileExists
        )
        #expect(secure.firmwareCodePath == "/Home/Library/Application Support/Veil/Firmware/edk2-aarch64-secure-code.fd")
        #expect(secure.firmwareVarsTemplatePath.hasSuffix("edk2-arm-secure-vars.fd"))

        let x86 = try LocalQEMUGuestBootPlanFactory.makePlan(
            for: guest(.x86_64), environment: [:], homeDirectory: home, bundledRuntimeDirectory: bundled, fileExists: fileExists
        )
        #expect(x86.executablePath == "/App/Runtime/bin/qemu-system-x86_64")
        #expect(x86.firmwareCodePath == "/App/Runtime/share/qemu/edk2-x86_64-code.fd")
        #expect(x86.firmwareVarsTemplatePath == "/App/Runtime/share/qemu/edk2-i386-vars.fd")
    }

    @Test("guest store round-trips guests in their own folders")
    func storeRoundTrip() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("veil-guest-store-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = GuestVMStore(rootDirectory: root)
        var created = store.makeGuest(.linuxArm64, name: "Debian", installerMediaPath: "/ISO/debian.iso", options: QEMUGuestBootOptions(tpm: true))
        // ISO 8601 keeps whole seconds only.
        created.profile.createdAt = Date(timeIntervalSince1970: 1_000)
        try store.save(created)

        #expect(try store.load(id: created.id) == created)
        #expect(store.list() == [created])
        #expect(created.profile.virtualDiskPath == store.directory(for: created.id).appendingPathComponent("disk.img").path)
    }

    @Test("a running guest is found by its disk, whichever QEMU binary runs it")
    func runningGuestDetection() {
        let output = """
          101 /usr/bin/other
          202 /Runtime/bin/qemu-system-x86_64 -name X -drive if=none,id=system,format=raw,file=/VMs/vm_test/disk.img,discard=unmap
          303 /Runtime/bin/qemu-system-aarch64 -drive if=none,id=system,format=raw,file=/VMs/vm_other/disk.img,discard=unmap
        """
        #expect(GuestVMLauncher.runningPID(virtualDiskPath: "/VMs/vm_test/disk.img", processListOutput: output) == 202)
        #expect(GuestVMLauncher.runningPID(virtualDiskPath: "/VMs/vm_missing/disk.img", processListOutput: output) == nil)
    }
}
