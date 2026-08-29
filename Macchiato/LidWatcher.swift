import CoreGraphics
import Foundation
import IOKit
import IOKit.hid

/// What to do with the built-in display while Keep Awake is on and the lid closes.
enum LidScreenMode: String, CaseIterable {
    case dimBrightness
    case sleepDisplay

    var title: String {
        switch self {
        case .dimBrightness: "Dim"
        case .sleepDisplay: "Sleep"
        }
    }

    private static let storageKey = "lidScreenMode"

    static var stored: LidScreenMode {
        LidScreenMode(rawValue: UserDefaults.standard.string(forKey: storageKey) ?? "") ?? .dimBrightness
    }

    func store() {
        UserDefaults.standard.set(rawValue, forKey: Self.storageKey)
    }
}

/// Thin binding to the DisplayServices private framework, which is the only
/// brightness path that still works on Apple Silicon — IODisplayConnect is
/// gone and CGDisplaySetBrightness has been removed from the SDK.
enum DisplayBrightnessService {
    private typealias GetFn = @convention(c) (UInt32, UnsafeMutablePointer<Float>) -> Int32
    private typealias SetFn = @convention(c) (UInt32, Float) -> Int32

    private static let handle: UnsafeMutableRawPointer? = dlopen(
        "/System/Library/PrivateFrameworks/DisplayServices.framework/DisplayServices", RTLD_LAZY
    )

    private static let getFn: GetFn? = handle
        .flatMap { dlsym($0, "DisplayServicesGetBrightness") }
        .map { unsafeBitCast($0, to: GetFn.self) }

    private static let setFn: SetFn? = handle
        .flatMap { dlsym($0, "DisplayServicesSetBrightness") }
        .map { unsafeBitCast($0, to: SetFn.self) }

    static var isAvailable: Bool { getFn != nil && setFn != nil }

    static func brightness(of displayID: CGDirectDisplayID) -> Double? {
        guard let getFn else { return nil }
        var value: Float = -1
        guard getFn(UInt32(displayID), &value) == 0, value >= 0 else { return nil }
        return Double(value)
    }

    @discardableResult
    static func setBrightness(_ value: Double, of displayID: CGDirectDisplayID) -> Bool {
        guard let setFn else { return false }
        return setFn(UInt32(displayID), Float(max(0, min(1, value)))) == 0
    }

    static func builtinDisplays() -> [CGDirectDisplayID] {
        var ids = [CGDirectDisplayID](repeating: 0, count: 16)
        var count: UInt32 = 0
        guard CGGetOnlineDisplayList(UInt32(ids.count), &ids, &count) == .success else { return [] }
        return ids.prefix(Int(count)).filter { CGDisplayIsBuiltin($0) != 0 }
    }
}

/// Saves the built-in display brightness and drops it to zero, restoring on demand.
@MainActor
final class DisplayDimmer {
    private(set) var isDimmed = false

    private var savedBrightness: [CGDirectDisplayID: Double] = [:]

    func dim() {
        guard !isDimmed, DisplayBrightnessService.isAvailable else { return }

        var savedAny = false
        for display in DisplayBrightnessService.builtinDisplays() {
            savedBrightness[display] = DisplayBrightnessService.brightness(of: display) ?? 1.0
            if DisplayBrightnessService.setBrightness(0, of: display) {
                savedAny = true
            }
        }

        isDimmed = savedAny
    }

    func restore() {
        guard isDimmed else { return }

        for (display, brightness) in savedBrightness {
            DisplayBrightnessService.setBrightness(brightness, of: display)
        }
        savedBrightness.removeAll()
        isDimmed = false
    }
}

enum ScreenPower {
    static func sleepDisplaysNow() {
        runCommand("/usr/bin/pmset", ["displaysleepnow"])
    }

    static func nudgeDisplaysAwake() {
        runCommand("/usr/bin/caffeinate", ["-u", "-t", "2"])
    }

    private static func runCommand(_ launchPath: String, _ arguments: [String]) {
        DispatchQueue.global(qos: .utility).async {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: launchPath)
            process.arguments = arguments
            do {
                try process.run()
                process.waitUntilExit()
            } catch {
                // Display power changes are best-effort.
            }
        }
    }
}

/// Polls the lid angle HID sensor and reports open/close transitions.
///
/// The sensor (vendor 0x05AC, product 0x8104, usage page 0x20 / usage 0x8A)
/// answers a feature report with the lid angle in degrees as a little-endian
/// UInt16 at buffer offset 1.
@MainActor
final class LidWatcher {
    static let closedThresholdDegrees = 10.0
    static let pollInterval: TimeInterval = 0.5

    /// Latest raw angle in degrees, nil when no readable sensor exists.
    private(set) var lidAngle: Double?
    private(set) var isLidClosed = false

    var onLidStateChanged: ((Bool) -> Void)?

    private var manager: IOHIDManager?
    private var device: IOHIDDevice?
    private var timer: Timer?
    private var reportBuffer = [UInt8](repeating: 0, count: 8)
    private var consecutiveClosedReads = 0
    private var consecutiveOpenReads = 0

    func start() {
        guard timer == nil else { return }

        if openSensorDevice() {
            lidAngle = nil
            consecutiveClosedReads = 0
            consecutiveOpenReads = 0

            poll()

            let timer = Timer(timeInterval: Self.pollInterval, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated { self?.poll() }
            }
            RunLoop.main.add(timer, forMode: .common)
            self.timer = timer
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil

        if let device {
            IOHIDDeviceClose(device, IOOptionBits(kIOHIDOptionsTypeNone))
        }
        if let manager {
            IOHIDManagerClose(manager, IOOptionBits(kIOHIDOptionsTypeNone))
        }
        device = nil
        manager = nil
        lidAngle = nil
        isLidClosed = false
        consecutiveClosedReads = 0
        consecutiveOpenReads = 0
    }

    private func openSensorDevice() -> Bool {
        let manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
        self.manager = manager

        for matching in [Self.strictMatching, Self.looseMatching] {
            IOHIDManagerSetDeviceMatching(manager, matching as CFDictionary)
            guard IOHIDManagerOpen(manager, IOOptionBits(kIOHIDOptionsTypeNone)) == kIOReturnSuccess,
                  let device = Self.firstDevice(from: manager) else {
                continue
            }
            guard IOHIDDeviceOpen(device, IOOptionBits(kIOHIDOptionsTypeNone)) == kIOReturnSuccess else {
                continue
            }
            self.device = device
            return true
        }

        return false
    }

    private static let strictMatching: [String: Any] = [
        kIOHIDVendorIDKey as String: 0x05AC,
        kIOHIDProductIDKey as String: 0x8104,
        kIOHIDDeviceUsagePageKey as String: 0x20,
        kIOHIDDeviceUsageKey as String: 0x8A,
    ]

    private static let looseMatching: [String: Any] = [
        kIOHIDDeviceUsagePageKey as String: 0x20,
        kIOHIDDeviceUsageKey as String: 0x8A,
    ]

    private static func firstDevice(from manager: IOHIDManager) -> IOHIDDevice? {
        guard let devices = IOHIDManagerCopyDevices(manager) else { return nil }

        var pointers = [UnsafeRawPointer?](repeating: nil, count: CFSetGetCount(devices))
        CFSetGetValues(devices, &pointers)
        guard let raw = pointers.compactMap({ $0 }).first else { return nil }
        return unsafeBitCast(raw, to: IOHIDDevice.self)
    }

    private func poll() {
        guard device != nil else { return }

        let angle = readAngle()
        lidAngle = angle

        guard let angle else { return }

        if angle <= Self.closedThresholdDegrees {
            consecutiveClosedReads += 1
            consecutiveOpenReads = 0

            if consecutiveClosedReads >= 2, !isLidClosed {
                isLidClosed = true
                onLidStateChanged?(true)
            }
        } else {
            consecutiveOpenReads += 1
            consecutiveClosedReads = 0

            if consecutiveOpenReads >= 1, isLidClosed {
                isLidClosed = false
                onLidStateChanged?(false)
            }
        }
    }

    private func readAngle() -> Double? {
        guard let device else { return nil }

        var length = CFIndex(reportBuffer.count)
        let result = IOHIDDeviceGetReport(
            device,
            kIOHIDReportTypeFeature,
            1,
            &reportBuffer,
            &length
        )

        guard result == kIOReturnSuccess, length >= 3 else { return nil }

        let raw = UInt16(reportBuffer[2]) << 8 | UInt16(reportBuffer[1])
        return Double(raw)
    }
}

/// Periodically asserts user activity so the screensaver / lock screen
/// cannot engage while the lid is closed. Fails safe: if the app exits,
/// the last `caffeinate` window expires within a minute and the normal
/// lock policy resumes.
@MainActor
final class LockScreenKeeper {
    static let windowSeconds = 40
    static let respawnInterval: TimeInterval = 20

    private(set) var isKeepingUnlocked = false

    private var process: Process?
    private var timer: Timer?

    func start() {
        guard timer == nil else { return }
        isKeepingUnlocked = true

        let timer = Timer(timeInterval: Self.respawnInterval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.ensureProcess() }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer

        ensureProcess()
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        if let process {
            process.terminate()
        }
        process = nil
        isKeepingUnlocked = false
    }

    private func ensureProcess() {
        guard isKeepingUnlocked else { return }
        if let process, process.isRunning { return }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/caffeinate")
        process.arguments = ["-u", "-t", String(Self.windowSeconds)]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
            self.process = process
        } catch {
            self.process = nil
        }
    }
}
