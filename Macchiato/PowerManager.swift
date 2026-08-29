import Foundation
import IOKit.pwr_mgt
import Observation

@MainActor
@Observable
final class PowerManager {
    static let shared = PowerManager()

    private(set) var isActive = false
    private(set) var isChanging = false
    private(set) var lastError: String?
    /// Set when Keep Awake backed off because the battery ran low.
    private(set) var stoppedDueToLowBattery = false

    var batteryLevel: Int? { batteryMonitor.batteryLevel }
    var isOnBatteryPower: Bool { batteryMonitor.isOnBatteryPower }
    var isLidClosed: Bool { lidWatcher.isLidClosed }

    var lidScreenMode: LidScreenMode = LidScreenMode.stored {
        didSet {
            guard oldValue != lidScreenMode else { return }
            lidScreenMode.store()
            applyLidState(lidWatcher.isLidClosed)
        }
    }

    /// Opt-in: while Keep Awake is on and the lid is closed, assert user
    /// activity so the screensaver / lock screen cannot engage.
    var preventLockWhileLidClosed: Bool {
        didSet {
            guard oldValue != preventLockWhileLidClosed else { return }
            UserDefaults.standard.set(
                preventLockWhileLidClosed,
                forKey: Self.preventLockStorageKey
            )
            updateLockKeeper()
        }
    }

    private static let preventLockStorageKey = "preventLockWhileLidClosed"

    private var assertionID: IOPMAssertionID = 0
    private let helper = PowerHelperClient.shared
    private let reason = "Macchiato is keeping your Mac awake" as CFString

    private let batteryMonitor = BatteryMonitor()
    private let lidWatcher = LidWatcher()
    private let dimmer = DisplayDimmer()
    private let lockKeeper = LockScreenKeeper()

    private init() {
        preventLockWhileLidClosed = UserDefaults.standard.bool(forKey: Self.preventLockStorageKey)
        batteryMonitor.onLowBattery = { [weak self] in
            Task { await self?.handleLowBattery() }
        }
        lidWatcher.onLidStateChanged = { [weak self] closed in
            self?.applyLidState(closed)
        }
    }

    func setActive(_ active: Bool) async {
        active ? await enable() : await disable()
    }

    func openHelperApprovalSettings() {
        helper.openHelperApprovalSettings()
    }

    func startMonitoring() {
        batteryMonitor.start()
        Notifier.requestAuthorization()
    }

    func enable() async {
        guard !isActive, !isChanging else { return }

        isChanging = true
        lastError = nil

        let result = IOPMAssertionCreateWithName(
            kIOPMAssertPreventUserIdleSystemSleep as CFString,
            IOPMAssertionLevel(kIOPMAssertionLevelOn),
            reason,
            &assertionID
        )

        guard result == kIOReturnSuccess else {
            assertionID = 0
            lastError = "Could not create power assertion."
            isChanging = false
            return
        }

        do {
            try await helper.setSleepDisabled(true)
            guard try await helper.isSleepDisabled() else {
                releaseAssertion()
                lastError = "Could not verify lid-closed sleep prevention."
                isChanging = false
                return
            }
            isActive = true
            stoppedDueToLowBattery = false
            lidWatcher.start()
            updateLockKeeper()
        } catch {
            releaseAssertion()
            lastError = error.localizedDescription
        }

        isChanging = false
    }

    func disable() async {
        guard isActive, !isChanging else { return }

        isChanging = true
        lastError = nil

        // Drop any lid-screen override before touching sleep state, so the
        // display is never left dark or asleep once Keep Awake is off.
        dimmer.restore()
        lockKeeper.stop()
        lidWatcher.stop()

        do {
            try await helper.setSleepDisabled(false)
            guard try await !helper.isSleepDisabled() else {
                lastError = "Could not verify normal sleep restoration."
                isChanging = false
                return
            }
            releaseAssertion()
            isActive = false
        } catch {
            lastError = error.localizedDescription
        }

        isChanging = false
    }

    private func releaseAssertion() {
        if assertionID != 0 {
            IOPMAssertionRelease(assertionID)
            assertionID = 0
        }
    }

    private func handleLowBattery() async {
        guard isActive, !isChanging else { return }

        let isFirstBackOff = !stoppedDueToLowBattery
        stoppedDueToLowBattery = true
        await disable()

        if !isActive, isFirstBackOff {
            await Notifier.postLowBatteryNotice(level: batteryMonitor.batteryLevel ?? 0)
        }
    }

    private func applyLidState(_ closed: Bool) {
        guard isActive else { return }

        if closed {
            switch lidScreenMode {
            case .dimBrightness where DisplayBrightnessService.isAvailable:
                dimmer.dim()
            case .dimBrightness, .sleepDisplay:
                ScreenPower.sleepDisplaysNow()
            }
        } else {
            dimmer.restore()
            if lidScreenMode == .sleepDisplay {
                ScreenPower.nudgeDisplaysAwake()
            }
        }

        updateLockKeeper()
    }

    private func updateLockKeeper() {
        let shouldRun = isActive
            && preventLockWhileLidClosed
            && lidWatcher.isLidClosed

        shouldRun ? lockKeeper.start() : lockKeeper.stop()
    }
}
