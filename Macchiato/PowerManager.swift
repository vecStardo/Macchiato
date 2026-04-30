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
    private let reason = "Macchiato is keeping your Mac awake" as CFString

    private init() {}

    func setActive(_ active: Bool) async {
        active ? await enable() : await disable()
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
            try await setDisableSleep(true)
            guard await isSleepDisabled() else {
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
            try await setDisableSleep(false)
            guard await !isSleepDisabled() else {
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

    private nonisolated func setDisableSleep(_ enabled: Bool) async throws {
        let value = enabled ? "1" : "0"
        let script = "do shell script \"/usr/bin/pmset -a disablesleep \(value)\" with administrator privileges"

        try await Task.detached(priority: .userInitiated) {
            let process = Process()
            let output = Pipe()

            process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
            process.arguments = ["-e", script]
            process.standardOutput = output
            process.standardError = output

            try process.run()
            process.waitUntilExit()

            if process.terminationStatus != 0 {
                let data = output.fileHandleForReading.readDataToEndOfFile()
                let message = String(data: data, encoding: .utf8)?
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                throw PowerManagerError.adminCommandFailed(message)
            }
        }.value
    }

    private nonisolated func isSleepDisabled() async -> Bool {
        await Task.detached(priority: .utility) {
            let process = Process()
            let output = Pipe()

            process.executableURL = URL(fileURLWithPath: "/usr/bin/pmset")
            process.arguments = ["-g", "live"]
            process.standardOutput = output
            process.standardError = output

            do {
                try process.run()
                process.waitUntilExit()
            } catch {
                return false
            }

            let data = output.fileHandleForReading.readDataToEndOfFile()
            let text = String(data: data, encoding: .utf8) ?? ""
            return text.range(of: #"SleepDisabled\s+1"#, options: .regularExpression) != nil
        }.value
    }

}

private enum PowerManagerError: LocalizedError {
    case adminCommandFailed(String?)

    var errorDescription: String? {
        switch self {
        case .adminCommandFailed(let message):
            if let message, !message.isEmpty {
                return message
            }
            return "Could not update lid-closed sleep setting."
        }
    }
}
