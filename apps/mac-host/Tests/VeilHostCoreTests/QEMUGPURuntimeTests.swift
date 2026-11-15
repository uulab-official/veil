import Foundation
import Testing
@testable import VeilHostCore

@Suite("GPU runtime")
struct QEMUGPURuntimeTests {
    private static let softwareArguments = [
        "-machine", "virt,highmem=on",
        "-accel", "hvf",
        "-device", "tpm-tis-device,tpmdev=tpm0,ppi=off",
        "-device", "virtio-rng-pci",
        "-display", "cocoa",
        "-device", "ramfb",
        "-device", "virtio-gpu-pci",
        "-device", "usb-kbd"
    ]

    @Test("The software plan's devices become Triton's")
    func rewritesPlanArguments() {
        #expect(QEMUGPURuntime.planArguments(Self.softwareArguments) == [
            "-machine", "virt,highmem=on",
            "-accel", "hvf,ipa-granule-size=0x1000",
            "-device", "tpm-tis-device,tpmdev=tpm0",
            "-device", "virtio-rng-pci",
            "-display", "egl-headless,gl=es",
            "-device", "virtio-ramfb-gl,hostmem=8G,blob=true,venus=false,neptune=true",
            "-device", "usb-kbd"
        ])
        // A Windows that already boots on virtio-gpu alone gets the same single device.
        let virtioOnly = ["-device", "virtio-gpu-pci", "-device", "usb-kbd"]
        #expect(QEMUGPURuntime.planArguments(virtioOnly) == [
            "-device", QEMUGPURuntime.displayDevice, "-device", "usb-kbd"
        ])
    }

    @Test("A windowless launch keeps the GL display backend")
    func launchKeepsGLDisplay() {
        #expect(QEMUGPURuntime.launchArguments(["-display", "none", "-vnc", "unix:/tmp/v"]) == [
            "-display", "egl-headless,gl=es", "-vnc", "unix:/tmp/v"
        ])
    }

    @Test("Software profiles are left alone")
    func softwareProfileUnchanged() {
        let plan = Self.plan()
        #expect(QEMUGPURuntime.applying(to: plan, profile: Self.profile(nil), runtime: Self.runtime) == plan)
        #expect(QEMUGPURuntime.applying(to: plan, profile: Self.profile(.software), runtime: Self.runtime) == plan)
    }

    @Test("A GPU profile runs on the GPU runtime with its environment")
    func gpuProfileMovesToRuntime() {
        let moved = QEMUGPURuntime.applying(to: Self.plan(), profile: Self.profile(.gpu), runtime: Self.runtime)
        #expect(moved.executablePath == "/Veil.app/Contents/Resources/RuntimeGPU/bin/qemu-system-aarch64")
        #expect(moved.isExecutableAvailable)
        #expect(moved.arguments.contains(QEMUGPURuntime.displayDevice))
        #expect(moved.processEnvironment?["RENDER_SERVER_EXEC_PATH"] == "/Veil.app/Contents/Resources/RuntimeGPU/libexec/virgl_render_server")
        #expect(moved.processEnvironment?["NPT_D3D11_LIBRARY_PATH"] == "/Veil.app/Contents/Resources/RuntimeGPU/lib/libdxmt-native.dylib")
        #expect(moved.processEnvironment?.keys.contains { $0.hasPrefix("DYLD_") } == false)
    }

    @Test("Without the runtime a GPU profile does not start blind on the software runtime")
    func missingRuntimeBlocksStart() {
        let blocked = QEMUGPURuntime.applying(to: Self.plan(), profile: Self.profile(.gpu), runtime: nil)
        #expect(!blocked.isExecutableAvailable)
        #expect(blocked.warnings.contains { $0.contains("GPU runtime") })
    }

    @Test("The launch planner keeps the GL display for a GPU plan")
    func launchPlannerKeepsGLDisplay() {
        let moved = QEMUGPURuntime.applying(to: Self.plan(), profile: Self.profile(.gpu), runtime: Self.runtime)
        let arguments = QEMUWindowsBootLaunchPlanner().makeArguments(
            from: moved,
            serialLogPath: "/tmp/serial.log",
            monitorSocketPath: "/tmp/m.sock",
            qmpSocketPath: "/tmp/q.qmp.sock",
            displayMode: .vncLoopback,
            vncSocketPath: "/tmp/v.sock"
        )
        let display = arguments.firstIndex(of: "-display").map { arguments[$0 + 1] }
        #expect(display == "egl-headless,gl=es")
        #expect(!arguments.contains("veil-shm-display,id=veilfb,path=/tmp/q.fb.sock"))
    }

    @Test("Veil's readiness check accepts a GPU plan")
    func readinessAcceptsGPUPlan() throws {
        var profile = Self.profile(.gpu)
        profile.installerMediaPath = "/Users/test/Win11.iso"
        profile.virtualDiskPath = "/Users/test/VM/Windows 11 Arm.img"
        profile.sharedFolderPath = "/Users/test/Veil Shared"
        let planner = QEMUWindowsBootPlanner(
            executablePath: "/Veil.app/Contents/Resources/Runtime/bin/qemu-system-aarch64",
            isExecutableAvailable: true,
            firmwarePath: "/Veil.app/Contents/Resources/Runtime/share/qemu/edk2-aarch64-code.fd",
            isFirmwareAvailable: true,
            firmwareVarsTemplatePath: "/Veil.app/Contents/Resources/Runtime/share/qemu/edk2-arm-vars.fd",
            isFirmwareVarsTemplateAvailable: true,
            firmwareVarsPath: "/Users/test/VM/uefi-vars.fd",
            isSecureBootFirmwareAvailable: false,
            tpmEmulatorPath: "/Veil.app/Contents/Resources/Runtime/bin/swtpm",
            isTPMEmulatorAvailable: true,
            tpmStateDirectoryPath: "/Users/test/VM/tpm"
        )
        let plan = QEMUGPURuntime.applying(to: try planner.makePlan(for: profile), profile: profile, runtime: Self.runtime)
        let report = QEMUWindowsReadinessDoctor(fileExists: { _ in true }).makeReport(profile: profile, plan: plan)
        let blocked = report.checks.filter { $0.state == .blocked }.map(\.id)
        #expect(blocked.isEmpty, "blocked: \(blocked)")
        #expect(report.overallState == .ready)
    }

    @Test("The runtime is complete only with QEMU, the render server and DXMT")
    func completeness() {
        let present: Set<String> = [
            "/R/bin/qemu-system-aarch64", "/R/libexec/virgl_render_server", "/R/lib/libdxmt-native.dylib"
        ]
        let runtime = QEMUGPURuntime(directory: URL(fileURLWithPath: "/R"))
        #expect(runtime.isComplete(fileExists: { present.contains($0) }))
        #expect(!runtime.isComplete(fileExists: { $0 != "/R/libexec/virgl_render_server" && present.contains($0) }))
    }

    @Test("A GPU session cannot be suspended")
    func gpuSessionIsNotSuspendable() {
        let process = QEMURunningProcess(pid: 1, commandLine: "qemu -device virtio-ramfb-gl,hostmem=8G -device virtio-blk")
        let snapshot = VMRuntimeSnapshot(
            state: .running,
            virtualizationAvailable: true,
            architecture: "arm64",
            minimumOSSupported: true,
            profileName: "Windows 11 Arm",
            virtualDiskPath: "/tmp/disk.img",
            runningQEMUProcess: process,
            runtimeProvider: VMRuntimeProviderSummary(
                kind: .qemuHypervisor,
                displayName: "QEMU",
                mode: "Local VM runtime",
                acceleration: "HVF",
                isServerBacked: false,
                status: .active,
                detail: "test"
            ),
            bootReady: true,
            detail: "running"
        )
        #expect(!VMSessionActionReportFactory.persistenceSummary(snapshot: snapshot).isSupported)
    }

    private static let runtime = QEMUGPURuntime(directory: URL(fileURLWithPath: "/Veil.app/Contents/Resources/RuntimeGPU"))

    private static func profile(_ graphics: VMGraphicsAcceleration?) -> VMProfile {
        var profile = VMProfile.defaultWindows11Arm(createdAt: Date(timeIntervalSince1970: 0))
        profile.graphicsAcceleration = graphics
        return profile
    }

    private static func plan() -> QEMUWindowsBootPlan {
        QEMUWindowsBootPlan(
            executablePath: "/Veil.app/Contents/Resources/Runtime/bin/qemu-system-aarch64",
            isExecutableAvailable: true,
            summary: "plan",
            arguments: softwareArguments,
            warnings: []
        )
    }
}
