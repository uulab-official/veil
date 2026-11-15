import Foundation

/// How Windows draws: on the CPU (Microsoft's WARP renderer on `virtio-gpu-pci`), or on the Mac's GPU
/// through Triton, UTM's DirectX 11 driver stack (`viogpu3d` in Windows, virglrenderer's Neptune
/// renderer and DXMT on the Mac). See docs/checklists/2026-11-10-triton-gpu-acceleration-evaluation.md.
public enum VMGraphicsAcceleration: String, Codable, CaseIterable, Equatable, Sendable {
    case software
    /// Experimental. Needs the GPU runtime in the app bundle and the `viogpu3d` driver in Windows. Once
    /// that driver is installed, Windows shows no display on the software runtime, so this choice is
    /// effectively one way for that Windows.
    case gpu
}

extension VMProfile {
    /// The profile's graphics choice; nil (every profile written before the setting existed) is software.
    public var effectiveGraphicsAcceleration: VMGraphicsAcceleration {
        graphicsAcceleration ?? .software
    }
}

/// The second QEMU Veil bundles for GPU acceleration: UTM's `utm-edition` fork (QEMU 10.0) with
/// virglrenderer, libepoxy, ANGLE and DXMT, built by `script/bundle_gpu_runtime.sh` into
/// `Contents/Resources/RuntimeGPU`. The software runtime (`VeilBundledRuntime`) stays the default, and
/// its firmware, TPM emulator and disk tools serve both.
public struct QEMUGPURuntime: Equatable, Sendable {
    public static let directoryName = "RuntimeGPU"
    public static let qemuExecutable = "bin/qemu-system-aarch64"
    public static let renderServer = "libexec/virgl_render_server"
    public static let d3d11Library = "lib/libdxmt-native.dylib"

    /// The display device. It carries a `ramfb` for firmware and Windows Setup and the GL virtio-gpu
    /// that `viogpu3d` binds; `hostmem` is the guest-visible window for shared GPU memory, address space
    /// rather than memory Veil allocates.
    public static let displayDevice = "virtio-ramfb-gl,hostmem=8G,blob=true,venus=false,neptune=true"
    /// Venus needs 4 KiB guest pages; Neptune works either way, and Triton's own setup uses 4 KiB.
    public static let accelerator = "hvf,ipa-granule-size=0x1000"
    /// A display backend with an OpenGL context and no window. ANGLE on Metal provides the context; Veil
    /// still reads the screen over VNC and the guest agent.
    public static let display = "egl-headless,gl=es"

    public var directory: URL

    public init(directory: URL) {
        self.directory = directory
    }

    /// The runtime inside the running app, or nil for a build without it.
    public static func bundled(
        bundle: Bundle = .main,
        fileExists: (String) -> Bool = { FileManager.default.fileExists(atPath: $0) }
    ) -> QEMUGPURuntime? {
        guard let directory = bundle.resourceURL?.appendingPathComponent(directoryName, isDirectory: true) else {
            return nil
        }
        let runtime = QEMUGPURuntime(directory: directory)
        return runtime.isComplete(fileExists: fileExists) ? runtime : nil
    }

    public var executablePath: String {
        directory.appendingPathComponent(Self.qemuExecutable).path
    }

    public func isComplete(fileExists: (String) -> Bool = { FileManager.default.fileExists(atPath: $0) }) -> Bool {
        [Self.qemuExecutable, Self.renderServer, Self.d3d11Library].allSatisfy {
            fileExists(directory.appendingPathComponent($0).path)
        }
    }

    /// Variables QEMU's process needs. virglrenderer starts its render server from a path fixed at build
    /// time unless told otherwise, and Neptune opens the D3D11 implementation by name; both are pointed
    /// into the bundle so nothing depends on the build Mac's folders. None of them is a `DYLD_` variable,
    /// which the hardened runtime would strip.
    public var processEnvironment: [String: String] {
        [
            "RENDER_SERVER_EXEC_PATH": directory.appendingPathComponent(Self.renderServer).path,
            "NPT_D3D11_LIBRARY_PATH": directory.appendingPathComponent(Self.d3d11Library).path,
            "NPT_BACKEND": "dxmt",
            "ANGLE_DEFAULT_PLATFORM": "metal"
        ]
    }

    /// The software plan's arguments, changed for this runtime.
    ///
    /// - The accelerator gets 4 KiB guest pages.
    /// - `ramfb` and `virtio-gpu-pci`, or `virtio-gpu-pci` alone, become the one GL device.
    /// - Any `-display` becomes the windowless GL backend, so the launch planner's later rewrite to `none`
    ///   is undone by `launchArguments(_:)`.
    /// - The TPM's `ppi=off` is dropped: QEMU 10.0's `tpm-tis-device` has no such property, and its PPI
    ///   region is the one QEMU 11 needed turning off.
    public static func planArguments(_ arguments: [String]) -> [String] {
        var result: [String] = []
        var index = 0
        var addedDisplayDevice = false
        while index < arguments.count {
            let argument = arguments[index]
            let value = index + 1 < arguments.count ? arguments[index + 1] : nil
            switch (argument, value) {
            case ("-accel", "hvf"?):
                result.append(contentsOf: ["-accel", accelerator])
                index += 2
            case ("-device", "ramfb"?), ("-device", "virtio-gpu-pci"?):
                if !addedDisplayDevice {
                    result.append(contentsOf: ["-device", displayDevice])
                    addedDisplayDevice = true
                }
                index += 2
            case ("-device", let device?) where device.hasPrefix("tpm-tis-device"):
                let options = device.split(separator: ",").filter { $0 != "ppi=off" }
                result.append(contentsOf: ["-device", options.joined(separator: ",")])
                index += 2
            case ("-display", _?):
                result.append(contentsOf: ["-display", display])
                index += 2
            default:
                result.append(argument)
                index += 1
            }
        }
        return result
    }

    /// The launch planner turns the display off for Veil's windowless modes; this runtime needs its GL
    /// backend there instead, or the GL device has no context to render into.
    public static func launchArguments(_ arguments: [String]) -> [String] {
        var result = arguments
        var index = 0
        while index + 1 < result.count {
            if result[index] == "-display" {
                result[index + 1] = display
            }
            index += 1
        }
        return result
    }

    /// The software plan, moved onto this runtime when the profile asks for GPU acceleration. With the
    /// runtime missing, the plan cannot run: a Windows with `viogpu3d` installed has no display on the
    /// software runtime, so falling back would boot it blind.
    public static func applying(
        to plan: QEMUWindowsBootPlan,
        profile: VMProfile,
        runtime: QEMUGPURuntime?
    ) -> QEMUWindowsBootPlan {
        guard profile.effectiveGraphicsAcceleration == .gpu else {
            return plan
        }
        var plan = plan
        plan.arguments = planArguments(plan.arguments)
        guard let runtime else {
            plan.isExecutableAvailable = false
            plan.warnings.append(
                "GPU acceleration is on for \(profile.name), but this copy of Veil has no GPU runtime (\(directoryName)). Install a Veil build that includes it, or turn GPU acceleration off if Windows has not installed its GPU driver yet."
            )
            return plan
        }
        plan.executablePath = runtime.executablePath
        plan.processEnvironment = runtime.processEnvironment
        plan.summary += " Graphics: GPU acceleration (Triton, experimental)."
        return plan
    }
}
