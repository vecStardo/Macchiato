import Foundation
import ServiceManagement

final class PowerHelperClient {
    static let shared = PowerHelperClient()

    private static let requestTimeoutNanoseconds: UInt64 = 8_000_000_000

    private let service = SMAppService.daemon(plistName: PowerHelperConstants.launchDaemonPlistName)
    private let connectionLock = NSLock()
    private var connection: NSXPCConnection?

    private init() {}

    func setSleepDisabled(_ disabled: Bool) async throws {
        try registerHelperIfNeeded()
        let connection = makeConnectionIfNeeded()

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            let once = ContinuationGate(continuation)
            let timeout = scheduleTimeout(for: once, connection: connection)

            guard let proxy = connection.remoteObjectProxyWithErrorHandler({ [weak self, weak connection] error in
                timeout.cancel()
                if let connection {
                    self?.resetConnection(connection)
                }
                once.resume(throwing: error)
            }) as? PowerHelperProtocol else {
                timeout.cancel()
                once.resume(throwing: PowerHelperClientError.unavailable)
                return
            }

            proxy.setSleepDisabled(disabled) { success, message in
                timeout.cancel()
                if success {
                    once.resume()
                } else {
                    once.resume(throwing: PowerHelperClientError.commandFailed(message))
                }
            }
        }
    }

    func isSleepDisabled() async throws -> Bool {
        try registerHelperIfNeeded()
        let connection = makeConnectionIfNeeded()

        return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Bool, Error>) in
            let once = ContinuationGate(continuation)
            let timeout = scheduleTimeout(for: once, connection: connection)

            guard let proxy = connection.remoteObjectProxyWithErrorHandler({ [weak self, weak connection] error in
                timeout.cancel()
                if let connection {
                    self?.resetConnection(connection)
                }
                once.resume(throwing: error)
            }) as? PowerHelperProtocol else {
                timeout.cancel()
                once.resume(throwing: PowerHelperClientError.unavailable)
                return
            }

            proxy.getSleepDisabled { disabled, message in
                timeout.cancel()
                if let message {
                    once.resume(throwing: PowerHelperClientError.commandFailed(message))
                } else {
                    once.resume(returning: disabled)
                }
            }
        }
    }

    func openHelperApprovalSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }

    private func registerHelperIfNeeded() throws {
        switch service.status {
        case .enabled:
            return
        case .notRegistered, .notFound:
            do {
                try service.register()
            } catch {
                if service.status == .requiresApproval {
                    throw PowerHelperClientError.requiresApproval
                }
                throw error
            }
            guard service.status == .enabled else {
                throw PowerHelperClientError.requiresApproval
            }
        case .requiresApproval:
            throw PowerHelperClientError.requiresApproval
        @unknown default:
            throw PowerHelperClientError.unavailable
        }
    }

    private func makeConnectionIfNeeded() -> NSXPCConnection {
        connectionLock.lock()
        defer { connectionLock.unlock() }

        if let connection {
            return connection
        }

        let newConnection = makeConnection()
        connection = newConnection
        return newConnection
    }

    private func makeConnection() -> NSXPCConnection {
        let connection = NSXPCConnection(
            machServiceName: PowerHelperConstants.machServiceName,
            options: .privileged
        )
        connection.remoteObjectInterface = NSXPCInterface(with: PowerHelperProtocol.self)
#if !DEBUG
        connection.setCodeSigningRequirement(PowerHelperConstants.helperCodeSigningRequirement)
#endif
        connection.invalidationHandler = { [weak self, weak connection] in
            if let connection {
                self?.clearConnection(connection)
            }
        }
        connection.resume()
        return connection
    }

    private func scheduleTimeout<Value>(
        for gate: ContinuationGate<Value>,
        connection: NSXPCConnection
    ) -> Task<Void, Never> {
        Task { [weak self, weak connection] in
            do {
                try await Task.sleep(nanoseconds: Self.requestTimeoutNanoseconds)
            } catch {
                return
            }

            guard !Task.isCancelled else { return }

            if let connection {
                self?.resetConnection(connection)
            }
            gate.resume(throwing: PowerHelperClientError.timedOut)
        }
    }

    private func resetConnection(_ connectionToInvalidate: NSXPCConnection) {
        clearConnection(connectionToInvalidate)
        connectionToInvalidate.invalidate()
    }

    private func clearConnection(_ connectionToClear: NSXPCConnection) {
        connectionLock.lock()
        defer { connectionLock.unlock() }

        if connection === connectionToClear {
            connection = nil
        }
    }
}

private final class ContinuationGate<Value> {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<Value, Error>?

    init(_ continuation: CheckedContinuation<Value, Error>) {
        self.continuation = continuation
    }

    func resume(returning value: Value) {
        take()?.resume(returning: value)
    }

    func resume(throwing error: Error) {
        take()?.resume(throwing: error)
    }

    func resume() where Value == Void {
        take()?.resume()
    }

    private func take() -> CheckedContinuation<Value, Error>? {
        lock.lock()
        defer { lock.unlock() }

        let current = continuation
        continuation = nil
        return current
    }
}

private enum PowerHelperClientError: LocalizedError {
    case commandFailed(String?)
    case notFound
    case requiresApproval
    case timedOut
    case unavailable

    var errorDescription: String? {
        switch self {
        case .commandFailed(let message):
            if let message, !message.isEmpty {
                return message
            }
            return "Could not update lid-closed sleep setting."
        case .notFound:
            return "Macchiato Helper is missing from the app bundle."
        case .requiresApproval:
            return "Approve Macchiato Helper in System Settings, then try again."
        case .timedOut:
            return "Macchiato Helper did not respond. Approve the helper in System Settings or relaunch Macchiato, then try again."
        case .unavailable:
            return "Macchiato Helper is unavailable."
        }
    }
}
