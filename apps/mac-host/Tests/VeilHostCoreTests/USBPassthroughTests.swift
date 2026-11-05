import Foundation
import Testing

@testable import VeilHostCore

@Suite("USB passthrough")
struct USBPassthroughTests {
    private static func entry(
        locationID: Int = 0x0110_0000,
        address: Int = 5,
        vendor: Int = 0x0781,
        product: Int = 0x5581,
        name: String? = "Ultra",
        deviceClass: Int = 0,
        builtIn: Bool? = nil,
        interfaces: [MacUSBRegistryEntry.Interface] = []
    ) -> MacUSBRegistryEntry {
        var properties: [String: MacUSBRegistryValue] = [
            "locationID": .integer(locationID),
            "USB Address": .integer(address),
            "idVendor": .integer(vendor),
            "idProduct": .integer(product),
            "bDeviceClass": .integer(deviceClass),
            "USB Vendor Name": .string("SanDisk")
        ]
        if let name {
            properties["USB Product Name"] = .string(name)
        }
        if let builtIn {
            properties["Built-In"] = .bool(builtIn)
        }
        return MacUSBRegistryEntry(properties: properties, interfaces: interfaces)
    }

    private static let storageStick = MacUSBDevice(
        locationID: 0x0110_0000,
        address: 5,
        vendorId: 0x0781,
        productId: 0x5581,
        productName: "Ultra",
        interfaceClasses: [0x08],
        isClaimedByMacDriver: true
    )

    @Test("reads bus and address the way libusb numbers them on macOS")
    func readsBusAndAddress() {
        let devices = MacUSBDeviceList.devices(from: [Self.entry(locationID: 0x0210_0000, address: 7)])

        // libusb's darwin backend uses the top byte of the location ID as the bus number, and QEMU's
        // hostbus/hostaddr filter compares against libusb's numbers.
        #expect(devices.count == 1)
        #expect(devices.first?.busNumber == 2)
        #expect(devices.first?.address == 7)
        #expect(devices.first?.vendorName == "SanDisk")
        #expect(devices.first?.qemuDeviceId == "veil-usb-0207-0781-5581")
    }

    @Test("leaves out hubs, built-in devices, and entries QEMU could not be pointed at")
    func leavesOutHubsAndBuiltIns() {
        var noAddress = Self.entry()
        noAddress.properties["USB Address"] = nil

        let devices = MacUSBDeviceList.devices(from: [
            Self.entry(deviceClass: 0x09),
            Self.entry(builtIn: true),
            noAddress,
            Self.entry(address: 9, name: nil)
        ])

        #expect(devices.map(\.address) == [9])
        #expect(devices.first?.displayName == "USB device 0781:5581")
    }

    @Test("flags a device a macOS driver owns, and warns for input and storage devices")
    func flagsDriverAndRisk() {
        let devices = MacUSBDeviceList.devices(from: [
            Self.entry(address: 1, interfaces: [.init(interfaceClass: 0x03, hasDriver: true)]),
            Self.entry(address: 2, interfaces: [.init(interfaceClass: 0x08, hasDriver: true)]),
            Self.entry(address: 3, interfaces: [.init(interfaceClass: 0xFF, hasDriver: false)])
        ])

        #expect(devices.map(\.risk) == [.inputDevice, .storage, .none])
        #expect(devices.map(\.isClaimedByMacDriver) == [true, true, false])
    }

    @Test("builds a usb-host device_add that pins bus, address, vendor, and product")
    func buildsDeviceAdd() throws {
        let line = try QEMUUSBPassthrough.attachCommand(for: Self.storageStick).jsonLine(id: "veil-qmp-0")
        let object = try #require(JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any])
        let arguments = try #require(object["arguments"] as? [String: Any])

        #expect(object["execute"] as? String == "device_add")
        #expect(arguments["driver"] as? String == "usb-host")
        #expect(arguments["id"] as? String == "veil-usb-0105-0781-5581")
        #expect(arguments["bus"] as? String == "usb0.0")
        #expect(arguments["hostbus"] as? Int == 1)
        #expect(arguments["hostaddr"] as? Int == 5)
        #expect(arguments["vendorid"] as? Int == 0x0781)
        #expect(arguments["productid"] as? Int == 0x5581)
    }

    @Test("builds device_del and the attached-property query")
    func buildsDeleteAndQuery() throws {
        let delete = try QEMUQMPCommand.deleteDevice(id: "veil-usb-0105-0781-5581").jsonLine(id: "a")
        let query = try QEMUQMPCommand.queryUSBDeviceAttached(id: "veil-usb-0105-0781-5581").jsonLine(id: "b")

        #expect(delete.contains(#""execute":"device_del""#))
        #expect(delete.contains(#""id":"veil-usb-0105-0781-5581""#))
        #expect(query.contains(#""execute":"qom-get""#))
        #expect(query.contains(#""path":"\/machine\/peripheral\/veil-usb-0105-0781-5581""#))
        #expect(query.contains(#""property":"attached""#))
    }

    @Test("parses a boolean qom-get return without mistaking numbers for booleans")
    func parsesBooleanReturn() {
        let replies = QEMUQMPClient.parseReplies(from: """
            {"return": true, "id": "a"}\r
            {"return": 1, "id": "b"}\r
            {"return": {}, "id": "c"}\r
            """)

        #expect(replies.map(\.boolReturn) == [true, nil, nil])
    }

    @Test("reads only Veil's devices out of info usb")
    func readsVeilDeviceIds() {
        // Captured from QEMU 11.1.3 with the boot plan's keyboard and tablet plus one Veil device.
        let output = "  Device 0.0, Port 1, Speed 480 Mb/s, Product QEMU USB Keyboard\r\n"
            + "  Device 0.0, Port 2, Speed 480 Mb/s, Product QEMU USB Tablet\r\n"
            + "  Device 0.0, Port 3, Speed 12 Mb/s, Product usb-storage, ID: installer-usb\r\n"
            + "  Device 0.0, Port 4, Speed 1.5 Mb/s, Product USB Host Device, ID: veil-usb-0105-0781-5581\r\n"

        #expect(QEMUUSBPassthrough.veilDeviceIds(fromInfoUSB: output) == ["veil-usb-0105-0781-5581"])
    }

    @Test("confirms the attach through QEMU's attached property")
    func confirmsAttach() async throws {
        let qmp = RecordingQMP(attachedAnswers: [false, true])
        let controller = QEMUUSBPassthroughController(qmp: qmp, pause: { _ in })

        try await controller.attach(Self.storageStick, qmpSocketPath: "/tmp/qmp.sock")

        let labels = await qmp.executeNames()
        #expect(labels == ["device_add", "qom-get", "qom-get"])
    }

    @Test("removes a device QEMU never claimed and says a macOS driver holds it")
    func removesUnclaimedDevice() async {
        let qmp = RecordingQMP(attachedAnswers: [false, false, false])
        let controller = QEMUUSBPassthroughController(qmp: qmp, pause: { _ in })

        await #expect(throws: USBPassthroughError.macDriverHoldsDevice(name: "Ultra")) {
            try await controller.attach(Self.storageStick, qmpSocketPath: "/tmp/qmp.sock")
        }
        // No half-attached usb-host may be left waiting in the VM.
        #expect(await qmp.executeNames().last == "device_del")
    }

    @Test("reports a device without a macOS driver that still failed differently")
    func reportsUnclaimedDriverlessDevice() async {
        var dongle = Self.storageStick
        dongle.isClaimedByMacDriver = false
        let controller = QEMUUSBPassthroughController(qmp: RecordingQMP(attachedAnswers: [false]), attachConfirmationAttempts: 1, pause: { _ in })

        await #expect(throws: USBPassthroughError.deviceNotClaimed(name: "Ultra")) {
            try await controller.attach(dongle, qmpSocketPath: "/tmp/qmp.sock")
        }
    }

    @Test("surfaces QEMU's refusal of device_add")
    func surfacesRefusal() async {
        let qmp = RecordingQMP(attachedAnswers: [], refuse: "device_add")
        let controller = QEMUUSBPassthroughController(qmp: qmp, pause: { _ in })

        await #expect(throws: USBPassthroughError.qemuRefused(message: "Bus 'usb0.0' is full")) {
            try await controller.attach(Self.storageStick, qmpSocketPath: "/tmp/qmp.sock")
        }
    }

    @Test("never removes a device Veil did not add")
    func refusesForeignDeviceIds() async {
        let qmp = RecordingQMP(attachedAnswers: [])
        let controller = QEMUUSBPassthroughController(qmp: qmp, pause: { _ in })

        await #expect(throws: USBPassthroughError.deviceNotFound) {
            try await controller.detach(deviceId: "installer-usb", qmpSocketPath: "/tmp/qmp.sock")
        }
        #expect(await qmp.executeNames().isEmpty)
    }

    @Test("detaches every Veil device before shutdown")
    func detachesAll() async {
        let qmp = RecordingQMP(
            attachedAnswers: [],
            infoUSB: "  Device 0.0, Port 1, Product QEMU USB Keyboard\r\n  Device 0.0, Port 4, Product USB Host Device, ID: veil-usb-0105-0781-5581\r\n  Device 0.0, Port 5, Product USB Host Device, ID: veil-usb-0106-1234-5678\r\n"
        )
        let controller = QEMUUSBPassthroughController(qmp: qmp, pause: { _ in })

        let removed = await controller.detachAll(qmpSocketPath: "/tmp/qmp.sock")

        #expect(removed == ["veil-usb-0105-0781-5581", "veil-usb-0106-1234-5678"])
        #expect(await qmp.executeNames() == ["human-monitor-command", "device_del", "device_del"])
    }

    @Test("snapshot shows attached devices and removes ones the Mac no longer has")
    func snapshotDropsUnpluggedDevices() async throws {
        let qmp = RecordingQMP(
            attachedAnswers: [],
            infoUSB: "  Device 0.0, Port 4, Product USB Host Device, ID: veil-usb-0105-0781-5581\r\n  Device 0.0, Port 5, Product USB Host Device, ID: veil-usb-0106-1234-5678\r\n"
        )
        let controller = QEMUUSBPassthroughController(qmp: qmp, pause: { _ in })

        let snapshot = try await controller.snapshot(macDevices: [Self.storageStick], qmpSocketPath: "/tmp/qmp.sock")

        #expect(snapshot.isVMRunning)
        #expect(snapshot.isAttached(Self.storageStick))
        #expect(snapshot.attachedDeviceIds == ["veil-usb-0105-0781-5581"])
        #expect(await qmp.deletedIds() == ["veil-usb-0106-1234-5678"])
    }

    @Test("a live QMP socket needs a running QEMU from the launch record")
    func liveSocketNeedsRunningProcess() {
        let record = QEMULaunchRecord(
            pid: 4242,
            executablePath: "/usr/bin/true",
            arguments: [],
            processLogPath: "/tmp/qemu.log",
            monitorSocketPath: "/tmp/monitor.sock",
            qmpSocketPath: NSTemporaryDirectory(),
            startedAt: Date(timeIntervalSince1970: 0)
        )

        #expect(LocalVMRuntimeService.liveQMPSocketPath(record, processIsRunning: { _ in true }) != nil)
        #expect(LocalVMRuntimeService.liveQMPSocketPath(record, processIsRunning: { _ in false }) == nil)
        #expect(LocalVMRuntimeService.liveQMPSocketPath(nil, processIsRunning: { _ in true }) == nil)
    }
}

private actor RecordingQMPLog {
    var commands: [QEMUQMPCommand] = []
    var attachedAnswers: [Bool]

    init(attachedAnswers: [Bool]) {
        self.attachedAnswers = attachedAnswers
    }

    func record(_ command: QEMUQMPCommand) -> Bool? {
        commands.append(command)
        guard case .queryUSBDeviceAttached = command else {
            return nil
        }
        return attachedAnswers.isEmpty ? false : attachedAnswers.removeFirst()
    }
}

private struct RecordingQMP: QEMUQMPControlling {
    let log: RecordingQMPLog
    let infoUSB: String
    let refuse: String?

    init(attachedAnswers: [Bool], infoUSB: String = "", refuse: String? = nil) {
        self.log = RecordingQMPLog(attachedAnswers: attachedAnswers)
        self.infoUSB = infoUSB
        self.refuse = refuse
    }

    func execute(_ commands: [QEMUQMPCommand], socketPath: String, idleTimeoutSeconds: Int) async throws -> [QEMUQMPReply] {
        var replies: [QEMUQMPReply] = []
        for command in commands {
            let attached = await log.record(command)
            if command.executeName == refuse {
                replies.append(QEMUQMPReply(id: nil, isSuccess: false, errorClass: "GenericError", errorMessage: "Bus 'usb0.0' is full"))
            } else if case .humanMonitor = command {
                replies.append(QEMUQMPReply(id: nil, isSuccess: true, textReturn: infoUSB))
            } else {
                replies.append(QEMUQMPReply(id: nil, isSuccess: true, boolReturn: attached))
            }
        }
        return replies
    }

    func executeNames() async -> [String] {
        await log.commands.map(\.executeName)
    }

    func deletedIds() async -> [String] {
        await log.commands.compactMap {
            if case .deleteDevice(let id) = $0 { return id }
            return nil
        }
    }
}
