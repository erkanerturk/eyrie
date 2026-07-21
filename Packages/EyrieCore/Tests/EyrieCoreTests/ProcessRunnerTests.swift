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

    @Test func launchFailureThrows() async {
        await #expect(throws: ProcessRunnerError.self) {
            _ = try await ProcessRunner.run("/nonexistent/binary")
        }
    }
}
