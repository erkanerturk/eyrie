import EyrieCore
import Foundation
@testable import TrafficKit

/// Replays scripted samples; repeats the last one once exhausted.
final class ScriptedSampler: ProcessTrafficSampling, @unchecked Sendable {
    private let lock = NSLock()
    private var queue: [[ProcessTraffic]?]
    private var last: [ProcessTraffic]?
    private var count = 0

    init(_ samples: [[ProcessTraffic]?] = []) {
        queue = samples
    }

    var sampleCount: Int {
        lock.withLock { count }
    }

    func sample() async -> [ProcessTraffic]? {
        lock.withLock {
            count += 1
            if queue.isEmpty { return last }
            let next = queue.removeFirst()
            last = next
            return next
        }
    }
}

/// Mutable fake clock, same shape as NetKit's.
final class FakeClock: @unchecked Sendable {
    private let lock = NSLock()
    private var date = Date(timeIntervalSinceReferenceDate: 800_000_000)

    var now: Date {
        lock.withLock { date }
    }

    func advance(by interval: TimeInterval) {
        lock.withLock { date = date.addingTimeInterval(interval) }
    }
}

/// Counts calls from the non-isolated `readCounters` closure.
final class CallCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0

    var value: Int { lock.withLock { count } }

    func increment() {
        lock.withLock { count += 1 }
    }
}

func process(_ pid: Int32, _ name: String, in bytesIn: UInt64, out bytesOut: UInt64) -> ProcessTraffic {
    ProcessTraffic(pid: pid, name: name, bytesIn: bytesIn, bytesOut: bytesOut)
}

func interface(
    _ name: String, in bytesIn: UInt64, out bytesOut: UInt64,
    up: Bool = true, running: Bool = true, loopback: Bool = false
) -> InterfaceCounters {
    InterfaceCounters(name: name, bytesIn: bytesIn, bytesOut: bytesOut,
                      isUp: up, isRunning: running, isLoopback: loopback)
}

/// Fresh suite-backed defaults per test, wiped on creation so reruns start
/// clean (self-cleaning rule).
func temporaryDefaults(_ token: String = UUID().uuidString) -> UserDefaults {
    let name = "traffickit-tests-\(token)"
    let defaults = UserDefaults(suiteName: name)!
    defaults.removePersistentDomain(forName: name)
    return defaults
}
