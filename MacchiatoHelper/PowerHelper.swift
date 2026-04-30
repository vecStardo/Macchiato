import Foundation

final class PowerHelper: NSObject, PowerHelperProtocol {
    func setSleepDisabled(_ disabled: Bool, withReply reply: @escaping (Bool, String?) -> Void) {
        let value = disabled ? "1" : "0"
        runPMSet(arguments: ["-a", "disablesleep", value], reply: reply)
    }

    func getSleepDisabled(withReply reply: @escaping (Bool, String?) -> Void) {
        do {
            let output = try runProcess(executable: "/usr/bin/pmset", arguments: ["-g", "live"])
            let disabled = output.range(of: #"SleepDisabled\s+1"#, options: .regularExpression) != nil
            reply(disabled, nil)
        } catch {
            reply(false, error.localizedDescription)
        }
    }

    private func runPMSet(arguments: [String], reply: @escaping (Bool, String?) -> Void) {
        do {
            _ = try runProcess(executable: "/usr/bin/pmset", arguments: arguments)
            reply(true, nil)
        } catch {
            reply(false, error.localizedDescription)
        }
    }

    private func runProcess(executable: String, arguments: [String]) throws -> String {
        let process = Process()
        let output = Pipe()

        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.standardOutput = output
        process.standardError = output

        try process.run()
        process.waitUntilExit()

        let data = output.fileHandleForReading.readDataToEndOfFile()
        let message = String(data: data, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        guard process.terminationStatus == 0 else {
            throw PowerHelperError.commandFailed(message)
        }

        return message
    }
}

private final class PowerHelperDelegate: NSObject, NSXPCListenerDelegate {
    private let helper = PowerHelper()

    func listener(_ listener: NSXPCListener, shouldAcceptNewConnection newConnection: NSXPCConnection) -> Bool {
        newConnection.exportedInterface = NSXPCInterface(with: PowerHelperProtocol.self)
        newConnection.exportedObject = helper
        newConnection.resume()
        return true
    }
}

private enum PowerHelperError: LocalizedError {
    case commandFailed(String)

    var errorDescription: String? {
        switch self {
        case .commandFailed(let message):
            return message.isEmpty ? "pmset failed." : message
        }
    }
}

@main
struct PowerHelperMain {
    static func main() {
        let listener = NSXPCListener(machServiceName: PowerHelperConstants.machServiceName)
        let delegate = PowerHelperDelegate()
#if !DEBUG
        listener.setConnectionCodeSigningRequirement(PowerHelperConstants.appCodeSigningRequirement)
#endif
        listener.delegate = delegate
        listener.resume()

        withExtendedLifetime((listener, delegate)) {
            RunLoop.main.run()
        }
    }
}
