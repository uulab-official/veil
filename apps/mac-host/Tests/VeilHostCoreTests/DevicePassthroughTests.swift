import Foundation
import Testing

@testable import VeilHostCore

/// Reports what Veil cannot do on this host, and why.
///
/// The value of these tests is not that a feature works — none of these features work. It is that the
/// report never claims a capability it does not have, never says "no" without a reason, and never
/// conflates a missing QEMU build option with a missing privilege, because those need different fixes.
@Suite("Device passthrough capability")
struct DevicePassthroughTests {
    @Test("reports usb-host as a privilege problem only when the device exists")
    func reportsPrivilegeProblemOnlyWhenDeviceExists() {
        let capability = VMDevicePassthroughReportFactory.usbPassthrough(
            qemuDeviceNames: ["usb-host", "usb-tablet"]
        )

        #expect(capability.state == .requiresPrivilegedHelper)
        #expect(capability.requiresPrivilegedHelper)
        #expect(capability.isAvailable == false)
        #expect(capability.prerequisite?.contains("without root") == true)
        #expect(capability.reference?.hasPrefix("https://") == true)
    }

    @Test("separates a QEMU built without libusb from a privilege problem")
    func separatesMissingDeviceFromPrivilegeProblem() {
        let capability = VMDevicePassthroughReportFactory.usbPassthrough(
            qemuDeviceNames: ["usb-tablet", "usb-kbd"]
        )

        // A build with no usb-host rejects the device as an unknown model rather than failing at access
        // time. Reporting that as a privilege problem would send someone chasing root when they need a
        // different QEMU.
        #expect(capability.state == .notBuiltIntoQEMU)
        #expect(capability.requiresPrivilegedHelper == false)
        #expect(capability.prerequisite?.contains("libusb") == true)
    }

    @Test("reports unknown rather than guessing when QEMU was not probed")
    func reportsUnknownWhenQEMUNotProbed() {
        let capability = VMDevicePassthroughReportFactory.usbPassthrough(qemuDeviceNames: nil)

        #expect(capability.state == .unknown)
        #expect(capability.requiresPrivilegedHelper == false)
        #expect(capability.prerequisite?.contains("unknown rather than assumed") == true)
    }

    @Test("every unavailable capability carries a reason")
    func everyUnavailableCapabilityCarriesAReason() {
        for deviceNames in [nil, [], ["usb-host"]] as [Set<String>?] {
            let report = VMDevicePassthroughReportFactory.make(
                generatedAt: Date(timeIntervalSince1970: 1_786_000_000),
                qemuExecutablePath: "/opt/homebrew/bin/qemu-system-aarch64",
                qemuDeviceNames: deviceNames
            )

            for capability in report.capabilities where !capability.isAvailable {
                #expect(capability.prerequisite != nil, "\(capability.id)")
            }
        }
    }

    @Test("the shipping network mode is always reported available")
    func shippingNetworkModeAlwaysAvailable() {
        let report = VMDevicePassthroughReportFactory.make(
            generatedAt: Date(timeIntervalSince1970: 1_786_000_000),
            qemuExecutablePath: nil,
            qemuDeviceNames: nil
        )
        let nat = report.capabilities.first { $0.id == VMDevicePassthroughReportFactory.sharedNATNetworkId }

        // If this were ever unavailable the guest would have no network at all, which is a much larger
        // problem than a missing passthrough mode.
        #expect(nat?.isAvailable == true)
        #expect(nat?.prerequisite == nil)
    }

    @Test("covers every capability a reader will ask about")
    func coversEveryCapability() {
        let report = VMDevicePassthroughReportFactory.make(
            generatedAt: Date(timeIntervalSince1970: 1_786_000_000),
            qemuExecutablePath: nil,
            qemuDeviceNames: nil
        )

        // Omitting a gap makes it disappear from the answer instead of being reported as unavailable.
        #expect(report.capabilities.map(\.id).sorted() == [
            VMDevicePassthroughReportFactory.bridgedNetworkId,
            VMDevicePassthroughReportFactory.hostOnlyNetworkId,
            VMDevicePassthroughReportFactory.sharedNATNetworkId,
            VMDevicePassthroughReportFactory.usbPassthroughId
        ].sorted())
        #expect(report.didProbeQEMU == false)
    }

    @Test("names the decision as a decision and rules out the dangerous shortcut")
    func namesTheDecisionAndRulesOutSudo() {
        let report = VMDevicePassthroughReportFactory.make(
            generatedAt: Date(timeIntervalSince1970: 1_786_000_000),
            qemuExecutablePath: "/opt/homebrew/bin/qemu-system-aarch64",
            qemuDeviceNames: ["usb-host"]
        )
        let joined = report.nextActions.joined(separator: " ")

        #expect(report.privilegedHelperDecision.contains("privileged helper"))
        #expect(report.privilegedHelperDecision.contains("sudo"))
        // Presented as an open decision, not pending work: a contributor reading "not implemented yet"
        // would start writing host code, and no amount of it closes this.
        #expect(joined.contains("decision"))
        #expect(joined.contains("sudo"))
    }

    @Test("surfaces the working alternative for every unavailable capability")
    func surfacesAlternativeForEveryUnavailableCapability() {
        let report = VMDevicePassthroughReportFactory.make(
            generatedAt: Date(timeIntervalSince1970: 1_786_000_000),
            qemuExecutablePath: "/opt/homebrew/bin/qemu-system-aarch64",
            qemuDeviceNames: ["usb-host"]
        )
        let joined = report.nextActions.joined(separator: " ")

        for capability in report.capabilities where !capability.isAvailable {
            guard let alternative = capability.alternative else {
                #expect(Bool(false), "\(capability.id) has no alternative")
                continue
            }

            #expect(joined.contains(alternative), "\(capability.id)")
        }
    }

    @Test("points at qemu-doctor when the installation could not be inspected")
    func pointsAtDoctorWhenInstallationUnknown() {
        let report = VMDevicePassthroughReportFactory.make(
            generatedAt: Date(timeIntervalSince1970: 1_786_000_000),
            qemuExecutablePath: nil,
            qemuDeviceNames: nil
        )

        #expect(report.nextActions.contains { $0.contains("qemu-doctor") })
    }

    @Test("reads only quoted device names out of -device help")
    func readsOnlyQuotedDeviceNames() {
        let output = """
            Storage devices:
            name "nvme", bus PCI
            name "usb-storage", bus usb-bus
            USB devices:
            name "usb-host", bus usb-bus, desc "USB Host Device"
            name "usb-tablet", bus usb-bus
            """

        let names = QEMUDeviceModelProbe.parseDeviceNames(from: output)

        // Only the quoted name is taken, so a bus or description mentioning a device-like word cannot be
        // mistaken for an available device.
        #expect(names.contains("usb-host"))
        #expect(names.contains("usb-tablet"))
        #expect(names.contains("nvme"))
        #expect(!names.contains("USB Host Device"))
        #expect(!names.contains("usb-bus"))
    }

    @Test("ignores lines with no parseable device name")
    func ignoresUnparseableLines() {
        #expect(QEMUDeviceModelProbe.parseDeviceNames(from: "").isEmpty)
        #expect(QEMUDeviceModelProbe.parseDeviceNames(from: "Storage devices:").isEmpty)
        // An unterminated quote is dropped rather than producing a truncated device name that could
        // accidentally match a real one.
        #expect(QEMUDeviceModelProbe.parseDeviceNames(from: "name \"usb-host").isEmpty)
        #expect(QEMUDeviceModelProbe.parseDeviceNames(from: "name \"\"").isEmpty)
    }

    @Test("treats a missing or non-executable QEMU as unprobed")
    func treatsMissingQEMUAsUnprobed() {
        #expect(QEMUDeviceModelProbe.deviceNames(qemuExecutablePath: nil) == nil)
        #expect(QEMUDeviceModelProbe.deviceNames(qemuExecutablePath: "   ") == nil)
        #expect(
            QEMUDeviceModelProbe.deviceNames(
                qemuExecutablePath: "/nonexistent/qemu-system-aarch64"
            ) == nil
        )
    }
}
