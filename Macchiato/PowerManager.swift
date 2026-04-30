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

    private var assertionID: IOPMAssertionID = 0
    private let helper = PowerHelperClient.shared
    private let reason = "Macchiato is keeping your Mac awake" as CFString

    private init() {}

    func setActive(_ active: Bool) async {
        active ? await enable() : await disable()
    }

    func openHelperApprovalSettings() {
        helper.openHelperApprovalSettings()
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
}
