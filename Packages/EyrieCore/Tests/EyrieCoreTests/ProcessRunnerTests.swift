import Testing
import EyrieCore

struct ProcessRunnerTests {
    @Test func capturesStandardOutput() async throws {
        let result = try await ProcessRunner.run("/bin/echo", arguments: ["hi"])
        #expect(result.terminationStatus == 0)
        #expect(result.standardOutput == "hi\n")
        #expect(result.standardError.isEmpty)
    }

    @Test func reportsNonZeroExit() async throws {
        let result = try await ProcessRunner.run("/usr/bin/false")
        #expect(result.terminationStatus != 0)
    }

    @Test func timesOutAndKillsTheChild() async {
        await #expect(throws: ProcessRunnerError.self) {
            _ = try await ProcessRunner.run(
                "/bin/sleep", arguments: ["30"], timeout: .milliseconds(200)
            )
        }
    }

    @Test func cancellationTerminatesTheChild() async {
        let started = ContinuousClock.now
        let task = Task {
            try await ProcessRunner.run("/bin/sleep", arguments: ["30"], timeout: .seconds(60))
        }
        try? await Task.sleep(for: .milliseconds(200))
        task.cancel()
        await #expect(throws: CancellationError.self) { _ = try await task.value }
        #expect(ContinuousClock.now - started < .seconds(5), "must not wait out the child or the timeout")
    }

    @Test func launchFailureThrows() async {
        await #expect(throws: ProcessRunnerError.self) {
            _ = try await ProcessRunner.run("/nonexistent/binary")
        }
    }
}
