import Foundation
import Testing
@testable import VeilHostCore

struct QEMUMemoryBalloonTests {
    private let gib = QEMUMemoryBalloonPolicy.gibibyte
    private let mib = QEMUMemoryBalloonPolicy.mebibyte

    private func stats(available: Int64, at time: Int64 = 1_000) -> GuestMemoryStatistics {
        GuestMemoryStatistics(availableBytes: available, lastUpdate: time)
    }

    @Test func shrinksIdleWindowsOneStepAtATime() {
        // 16 GiB Windows using 3 GiB: wants 3 + 3.2 cushion = 6.25 GiB, so it shrinks by 1 GiB.
        let target = QEMUMemoryBalloonPolicy.target(
            configuredBytes: 16 * gib, actualBytes: 16 * gib,
            statistics: stats(available: 13 * gib), pressure: .normal, now: 1_005
        )
        #expect(target == 15 * gib)
    }

    @Test func growsAtOnceWhenWindowsNeedsMemory() {
        let target = QEMUMemoryBalloonPolicy.target(
            configuredBytes: 16 * gib, actualBytes: 6 * gib,
            statistics: stats(available: 512 * mib), pressure: .normal, now: 1_005
        )
        // Used 5.5 GiB plus the 3.2 GiB cushion, rounded up to 256 MiB.
        #expect(target == 8960 * mib)
    }

    @Test func keepsAStableSizeAndTheFloor() {
        // Within the hysteresis band: leave it.
        #expect(QEMUMemoryBalloonPolicy.target(
            configuredBytes: 16 * gib, actualBytes: 6656 * mib,
            statistics: stats(available: 3 * gib + 512 * mib), pressure: .normal, now: 1_005
        ) == nil)
        // Nearly idle Windows never goes below 4 GiB.
        #expect(QEMUMemoryBalloonPolicy.target(
            configuredBytes: 16 * gib, actualBytes: 5 * gib,
            statistics: stats(available: 4 * gib + 768 * mib), pressure: .critical, now: 1_005
        ) == 4 * gib)
    }

    @Test func macMemoryPressureShrinksTheCushion() {
        #expect(QEMUMemoryBalloonPolicy.cushionBytes(configuredBytes: 16 * gib, pressure: .normal) == 16 * gib / 5)
        #expect(QEMUMemoryBalloonPolicy.cushionBytes(configuredBytes: 16 * gib, pressure: .warning) == 16 * gib / 10)
        #expect(QEMUMemoryBalloonPolicy.cushionBytes(configuredBytes: 16 * gib, pressure: .critical) == 512 * mib)
    }

    @Test func givesEverythingBackWithoutFreshStatistics() {
        #expect(QEMUMemoryBalloonPolicy.target(
            configuredBytes: 16 * gib, actualBytes: 8 * gib, statistics: nil, pressure: .normal, now: 1_000
        ) == 16 * gib)
        #expect(QEMUMemoryBalloonPolicy.target(
            configuredBytes: 16 * gib, actualBytes: 8 * gib,
            statistics: stats(available: 7 * gib, at: 900), pressure: .normal, now: 1_000
        ) == 16 * gib)
        #expect(QEMUMemoryBalloonPolicy.target(
            configuredBytes: 16 * gib, actualBytes: 16 * gib, statistics: nil, pressure: .normal, now: 1_000
        ) == nil)
    }

    @Test func readsDriverStatisticsAndBalloonSizeFromQMP() {
        let replies = QEMUQMPClient.parseReplies(from: """
        {"return": {"actual": 17179869184}, "id": "veil-qmp-0"}
        {"return": {"stats": {"stat-available-memory": 12884901888, "stat-free-memory": 8589934592, "stat-htlb-pgalloc": -1}, "last-update": 1762740000}, "id": "veil-qmp-1"}
        """)
        #expect(replies[0].balloonActualBytes == 16 * gib)
        let statistics = replies[1].balloonStatistics.flatMap(GuestMemoryStatistics.init(qmpStatistics:))
        #expect(statistics == GuestMemoryStatistics(availableBytes: 12 * gib, lastUpdate: 1_762_740_000))
        // Before the driver's first report QEMU sends -1 values and a zero last-update.
        #expect(GuestMemoryStatistics(qmpStatistics: ["stat-available-memory": -1, "last-update": 0]) == nil)
    }

    @Test func encodesBalloonCommands() throws {
        #expect(try QEMUQMPCommand.setBalloonTarget(bytes: 4 * gib).jsonLine(id: "a")
            == #"{"arguments":{"value":4294967296},"execute":"balloon","id":"a"}"#)
        #expect(try QEMUQMPCommand.queryBalloonStatistics(deviceID: "veil-balloon").jsonLine(id: "b")
            == #"{"arguments":{"path":"\/machine\/peripheral\/veil-balloon","property":"guest-stats"},"execute":"qom-get","id":"b"}"#)
    }

    @Test func sizesTheBalloonOnlyOnAPatchedBundledQEMU() {
        let bundled = "/Applications/Veil.app/Contents/Resources/Runtime/bin/qemu-system-aarch64"
        let patch = "/Applications/Veil.app/Contents/Resources/Runtime/licenses/qemu-patches/\(QEMUMemoryBalloon.releasePatchFileName)"
        #expect(QEMUMemoryBalloon.releasesMemoryToMac(executablePath: bundled, fileExists: { $0 == patch }))
        #expect(!QEMUMemoryBalloon.releasesMemoryToMac(executablePath: "/opt/homebrew/bin/qemu-system-aarch64", fileExists: { $0 == patch }))
    }

    @Test func findsTheDeviceAndMemorySizeInLaunchArguments() {
        let arguments = ["-m", "16384M"] + QEMUMemoryBalloon.deviceArguments
        #expect(QEMUMemoryBalloon.isAttached(arguments: arguments))
        #expect(!QEMUMemoryBalloon.isAttached(arguments: ["-device", "virtio-rng-pci"]))
        #expect(LocalVMRuntimeService.configuredMemoryBytes(arguments: arguments) == 16 * gib)
    }
}
