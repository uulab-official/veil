import Foundation
import VeilHostCore

/// `veil-vmctl guest-*`: create and boot non-Windows guests (Linux Arm64, emulated x86_64).
///
/// These commands never read or write the Windows profile; guests live in `GuestVMStore`.
enum GuestCommand: Equatable {
    case create(json: Bool, os: VMGuestOS, name: String?, installerPath: String?, cpus: Int?, memoryMB: Int?, diskGB: Int?, options: QEMUGuestBootOptions)
    case list(json: Bool)
    case plan(json: Bool, id: String)
    case start(json: Bool, id: String, headless: Bool)
    case capture(json: Bool, id: String, outputPath: String)
    case stop(json: Bool, id: String, force: Bool)

    static let usage = "veil-vmctl guest-create --os linux-arm64|x86_64 --iso /path/to/installer.iso [--name N] [--cpus N] [--memory-mb N] [--disk-gb N] [--tpm] [--secure-boot] [--json] | veil-vmctl guest-list [--json] | veil-vmctl guest-plan --id ID [--json] | veil-vmctl guest-start --id ID [--headless] [--json] | veil-vmctl guest-capture --id ID --output /path/to/console.png [--json] | veil-vmctl guest-stop --id ID [--force] [--json]"

    enum ParseError: Error, LocalizedError {
        case invalid(String)

        var errorDescription: String? {
            switch self {
            case .invalid(let detail): "\(detail) Usage: \(GuestCommand.usage)"
            }
        }
    }

    /// `nil` when `arguments` is not a guest command.
    static func parse(_ arguments: [String]) throws -> GuestCommand? {
        guard let command = arguments.first, command.hasPrefix("guest-"), command != "guest-agent-wait" else {
            return nil
        }
        let json = arguments.contains("--json")
        func value(_ name: String) -> String? {
            guard let index = arguments.firstIndex(of: name), arguments.indices.contains(index + 1) else {
                return nil
            }
            return arguments[index + 1]
        }
        func requiredID() throws -> String {
            guard let id = value("--id"), !id.isEmpty else {
                throw ParseError.invalid("Missing --id.")
            }
            return id
        }

        switch command {
        case "guest-create":
            guard let osValue = value("--os"), let os = VMGuestOS(rawValue: osValue), os != .windows11Arm else {
                throw ParseError.invalid("Pass --os linux-arm64 or --os x86_64; Windows uses veil-vmctl prepare.")
            }
            return .create(
                json: json,
                os: os,
                name: value("--name"),
                installerPath: value("--iso"),
                cpus: value("--cpus").flatMap(Int.init),
                memoryMB: value("--memory-mb").flatMap(Int.init),
                diskGB: value("--disk-gb").flatMap(Int.init),
                options: QEMUGuestBootOptions(tpm: arguments.contains("--tpm"), secureBoot: arguments.contains("--secure-boot"))
            )
        case "guest-list":
            return .list(json: json)
        case "guest-plan":
            return .plan(json: json, id: try requiredID())
        case "guest-start":
            return .start(json: json, id: try requiredID(), headless: arguments.contains("--headless"))
        case "guest-capture":
            guard let output = value("--output") else {
                throw ParseError.invalid("Missing --output.")
            }
            return .capture(json: json, id: try requiredID(), outputPath: output)
        case "guest-stop":
            return .stop(json: json, id: try requiredID(), force: arguments.contains("--force"))
        default:
            throw ParseError.invalid("Unsupported command '\(command)'.")
        }
    }
}

extension VeilVMControl {
    static func runGuestCommand(_ command: GuestCommand, store: GuestVMStore = GuestVMStore()) throws {
        switch command {
        case .create(let json, let os, let name, let installerPath, let cpus, let memoryMB, let diskGB, let options):
            if let installerPath, !FileManager.default.fileExists(atPath: installerPath) {
                throw VMControlError.installerNotFound(installerPath)
            }
            let defaults = os.defaultResources
            let resources = VMResourcePlan(
                cpuCount: cpus ?? defaults.cpuCount,
                memoryMB: memoryMB ?? defaults.memoryMB,
                diskGB: diskGB ?? defaults.diskGB
            )
            let guest = store.makeGuest(
                os,
                name: name ?? os.displayName,
                installerMediaPath: installerPath.map { URL(fileURLWithPath: $0).standardizedFileURL.path },
                options: options,
                resources: resources
            )
            try store.save(guest)
            try printGuest(guest, json: json, store: store)
        case .list(let json):
            let guests = store.list()
            if json {
                try printJSON(guests)
            } else {
                for guest in guests {
                    print("\(guest.id)\t\(guest.profile.guestOS.rawValue)\t\(guest.profile.name)")
                }
            }
        case .plan(let json, let id):
            let guest = try store.load(id: id)
            let plan = try LocalQEMUGuestBootPlanFactory.makePlan(for: guest.profile, options: guest.options)
            if json {
                try printJSON(plan)
            } else {
                print(([plan.executablePath] + plan.arguments).joined(separator: " "))
                plan.warnings.forEach { print("warning: \($0)") }
            }
        case .start(let json, let id, let headless):
            let guest = try store.load(id: id)
            let plan = try LocalQEMUGuestBootPlanFactory.makePlan(for: guest.profile, options: guest.options)
            let record = try GuestVMLauncher.launch(guest, plan: plan, display: headless ? .none : .cocoa)
            if json {
                try printJSON(record)
            } else {
                print("Started \(guest.profile.name) as QEMU PID \(record.pid). Log: \(record.processLogPath)")
                plan.warnings.forEach { print("warning: \($0)") }
            }
        case .capture(let json, let id, let outputPath):
            let socket = try monitorSocket(for: id, store: store)
            let imageURL = URL(fileURLWithPath: outputPath)
            try? FileManager.default.removeItem(at: imageURL)
            QEMUVMRuntimeBooter.captureConsoleScreenshot(monitorSocketURL: socket, imageURL: imageURL)
            guard FileManager.default.fileExists(atPath: imageURL.path) else {
                throw VMControlError.qemuScreenshotCaptureFailed(outputPath)
            }
            json ? try printJSON(["path": imageURL.path]) : print(imageURL.path)
        case .stop(let json, let id, let force):
            let socket = try monitorSocket(for: id, store: store)
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/bin/sh")
            process.arguments = ["-c", "printf '%s\\n' \"$1\" | /usr/bin/nc -w 2 -U \"$0\"", socket.path, force ? "quit" : "system_powerdown"]
            process.standardOutput = FileHandle.nullDevice
            try process.run()
            process.waitUntilExit()
            json ? try printJSON(["sent": force ? "quit" : "system_powerdown"]) : print(force ? "Sent quit." : "Sent system_powerdown.")
        }
    }

    private static func monitorSocket(for id: String, store: GuestVMStore) throws -> URL {
        let guest = try store.load(id: id)
        guard let pid = GuestVMLauncher.runningPID(virtualDiskPath: guest.profile.virtualDiskPath),
              let path = runningMonitorSocketPath(pid: pid) else {
            throw VMControlError.qemuMonitorUnavailable(guest.profile.name)
        }
        return URL(fileURLWithPath: path)
    }

    private static func runningMonitorSocketPath(pid: Int32) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/ps")
        process.arguments = ["-o", "command=", "-p", "\(pid)"]
        let pipe = Pipe()
        process.standardOutput = pipe
        guard (try? process.run()) != nil else {
            return nil
        }
        let command = String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        process.waitUntilExit()
        guard let range = command.range(of: "-monitor unix:") else {
            return nil
        }
        return command[range.upperBound...].split(separator: ",").first.map(String.init)
    }

    private static func printGuest(_ guest: GuestVM, json: Bool, store: GuestVMStore) throws {
        if json {
            try printJSON(guest)
        } else {
            print("Created \(guest.profile.name) (\(guest.profile.guestOS.displayName)) as \(guest.id) in \(store.directory(for: guest.id).path)")
        }
    }

    private static func printJSON<T: Encodable>(_ value: T) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        print(String(decoding: try encoder.encode(value), as: UTF8.self))
    }
}
