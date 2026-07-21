import Foundation
import Synchronization

public struct ProcessOutput: Sendable, Equatable {
    public let terminationStatus: Int32
    public let standardOutput: String
    public let standardError: String

    public init(terminationStatus: Int32, standardOutput: String, standardError: String) {
        self.terminationStatus = terminationStatus
        self.standardOutput = standardOutput
        self.standardError = standardError
    }
}

public enum ProcessRunnerError: Error {
    case timedOut
    case launchFailed(any Error)
}

/// One-shot runner for short, absolute-path tool invocations. Long-lived
/// streaming children don't belong here — own those in an actor.
public enum ProcessRunner {
    public static func run(
        _ executablePath: String,
        arguments: [String] = [],
        timeout: Duration = .seconds(5)
    ) async throws -> ProcessOutput {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executablePath)
        process.arguments = arguments
        process.standardInput = FileHandle.nullDevice
        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr

        // Registered before run() so an instantly-exiting child can't slip
        // past the handler.
        let exitEvents = AsyncStream<Int32> { continuation in
            process.terminationHandler = { child in
                continuation.yield(child.terminationStatus)
                continuation.finish()
            }
        }

        do {
            try process.run()
        } catch {
            throw ProcessRunnerError.launchFailed(error)
        }

        let timedOut = Mutex(false)
        let child = UncheckedSendableBox(process)
        let watchdog = Task.detached {
            try? await Task.sleep(for: timeout)
            guard !Task.isCancelled else { return }
            timedOut.withLock { $0 = true }
            child.value.terminate()
            try? await Task.sleep(for: .seconds(1))
            if child.value.isRunning {
                kill(child.value.processIdentifier, SIGKILL)
            }
        }
        defer { watchdog.cancel() }

        // Drain both pipes while the child runs; a child that fills a pipe
        // buffer before exiting would otherwise deadlock against readToEnd.
        async let stdoutData = readToEnd(stdout.fileHandleForReading)
        async let stderrData = readToEnd(stderr.fileHandleForReading)

        var status: Int32 = -1
        for await exitStatus in exitEvents {
            status = exitStatus
        }
        let output = await ProcessOutput(
            terminationStatus: status,
            standardOutput: String(data: stdoutData, encoding: .utf8) ?? "",
            standardError: String(data: stderrData, encoding: .utf8) ?? ""
        )

        if timedOut.withLock({ $0 }) {
            throw ProcessRunnerError.timedOut
        }
        return output
    }

    private static func readToEnd(_ handle: FileHandle) async -> Data {
        var data = Data()
        do {
            for try await byte in handle.bytes {
                data.append(byte)
            }
        } catch {
            // Partial output is still useful (e.g. after a timeout kill).
        }
        return data
    }
}

/// Process is thread-safe for terminate()/isRunning but not Sendable; this
/// box only crosses it into the watchdog task.
private final class UncheckedSendableBox<Value>: @unchecked Sendable {
    let value: Value
    init(_ value: Value) { self.value = value }
}
