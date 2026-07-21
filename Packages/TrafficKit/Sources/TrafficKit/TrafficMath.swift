import Foundation

public enum TrafficMath {
    /// Rates from two consecutive cumulative frames. A pid with no previous
    /// row, a counter regression (pid reuse, nettop restart) or a zero
    /// elapsed keeps the totals but reports a zero rate — totals render
    /// immediately, rates fill in one tick later.
    public static func rates(
        previous: [ProcessTraffic],
        current: [ProcessTraffic],
        elapsed: TimeInterval
    ) -> [ProcessTrafficRate] {
        let previousByPid = Dictionary(previous.map { ($0.pid, $0) }) { first, _ in first }
        return current.map { row in
            var inPerSecond = 0.0
            var outPerSecond = 0.0
            if elapsed > 0,
               let before = previousByPid[row.pid],
               before.bytesIn <= row.bytesIn, before.bytesOut <= row.bytesOut {
                inPerSecond = Double(row.bytesIn - before.bytesIn) / elapsed
                outPerSecond = Double(row.bytesOut - before.bytesOut) / elapsed
            }
            return ProcessTrafficRate(
                pid: row.pid, name: row.name,
                bytesIn: row.bytesIn, bytesOut: row.bytesOut,
                inPerSecond: inPerSecond, outPerSecond: outPerSecond
            )
        }
    }

    /// Biggest cumulative consumers first — "who used how much".
    public static func topConsumers(_ rates: [ProcessTrafficRate], count: Int) -> [ProcessTrafficRate] {
        Array(rates.sorted { $0.totalBytes > $1.totalBytes }.prefix(max(0, count)))
    }
}
