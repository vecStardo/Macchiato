import Foundation
import IOKit.ps
import Observation
import UserNotifications

/// Watches the internal battery and fires a one-shot callback when the Mac
/// runs on battery power at or below the low-battery threshold.
@MainActor
@Observable
final class BatteryMonitor {
    static let lowBatteryThresholdPercent = 10
    static let pollInterval: TimeInterval = 30

    /// Percentage 0...100, or nil when the Mac has no readable battery.
    private(set) var batteryLevel: Int?
    private(set) var isOnBatteryPower = false
    /// Set while the low-battery condition holds, cleared once it lifts.
    private(set) var isLowBattery = false

    /// Called on the main actor when Keep Awake should back off.
    var onLowBattery: (() -> Void)?

    private var timer: Timer?

    func start() {
        refresh()

        let timer = Timer(timeInterval: Self.pollInterval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    func refresh() {
        let snapshot = Self.readPowerSource()

        batteryLevel = snapshot?.level
        isOnBatteryPower = snapshot?.isOnBattery ?? false

        let isLow = (snapshot?.level ?? .max) <= Self.lowBatteryThresholdPercent
            && (snapshot?.isOnBattery ?? false)

        // Fire on every refresh while the condition holds, so a trigger missed
        // mid-toggle is picked up by the next poll.
        if isLow {
            onLowBattery?()
        }
        isLowBattery = isLow
    }

    private struct Snapshot {
        let level: Int
        let isOnBattery: Bool
    }

    private static func readPowerSource() -> Snapshot? {
        guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let sources = IOPSCopyPowerSourcesList(info)?.takeRetainedValue() as? [CFTypeRef] else {
            return nil
        }

        for source in sources {
            guard let description = IOPSGetPowerSourceDescription(info, source)?
                .takeUnretainedValue() as? [String: Any],
                let level = description[kIOPSCurrentCapacityKey] as? Int else {
                continue
            }

            let state = description[kIOPSPowerSourceStateKey] as? String
            return Snapshot(level: level, isOnBattery: state == kIOPSBatteryPowerValue)
        }

        return nil
    }
}

/// Local notifications for events the user should know about after the fact.
enum Notifier {
    static func requestAuthorization() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert]) { _, _ in
            // Notifications are optional; the features work without them.
        }
    }

    static func postLowBatteryNotice(level: Int) async {
        let content = UNMutableNotificationContent()
        content.title = "Macchiato"
        content.body = String.localizedStringWithFormat(
            NSLocalizedString(
                "Battery at %lld%%. Keep Awake turned off so your Mac can sleep.",
                comment: "low-battery notification body"
            ),
            level
        )
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        try? await UNUserNotificationCenter.current().add(request)
    }
}
