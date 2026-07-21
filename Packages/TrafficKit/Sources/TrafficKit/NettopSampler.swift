import EyrieCore
import Foundation

public protocol ProcessTrafficSampling: Sendable {
    /// One complete cumulative snapshot. nil means nettop is unusable
    /// (missing, failed, or its output format drifted).
    func sample() async -> [ProcessTraffic]?
}

/// One-shot `nettop` per tick.
///
/// A persistent `nettop -L 0` child looks cheaper but is unusable: it
/// block-buffers into a pipe, so the first line arrived only after ~36 s
/// (measured). A one-shot run costs ~8 ms of CPU and returns immediately —
/// **as long as `-n` is passed**, since address-to-name resolution alone
/// accounts for a fixed ~5 s delay (5.04 s → 0.01 s, measured). No long-lived
/// child also means nothing to reap on quit.
public struct LiveNettopSampler: ProcessTrafficSampling {
    public init() {}

    public func sample() async -> [ProcessTraffic]? {
        guard let output = try? await ProcessRunner.run(
            "/usr/bin/nettop",
            arguments: [
                "-P",              // per-process summary, not per-flow
                "-x",              // raw byte counts
                "-L", "1",         // one CSV sample, then exit
                "-n",              // no name resolution — the 5 s delay lives here
                "-t", "external",  // skip loopback: "network usage" means off-box
                "-J", "bytes_in,bytes_out",
            ],
            timeout: .seconds(10)
        ), output.terminationStatus == 0 else { return nil }

        var lines = output.standardOutput
            .split(separator: "\n", omittingEmptySubsequences: true)
            .map(String.init)
        guard let header = lines.first, NettopParser.isValidHeader(header) else { return nil }
        lines.removeFirst()
        return NettopParser.parseFrame(lines)
    }
}
