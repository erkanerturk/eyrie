import Darwin
import EyrieCore
import Foundation

enum MetricsError: Error {
    case machCall(String, kern_return_t)
    case sysctl(String, Int32)
}

/// Reads raw system counters via public Mach/sysctl APIs. All unsafe-pointer
/// code in StatsKit is confined to this file.
public struct LiveSystemMetricsProvider: SystemMetricsProviding {
    /// Cached because every mach_host_self() call takes out a new port right.
    private let hostPort: mach_port_t
    /// vm_kernel_page_size is a global var (not concurrency-safe under Swift 6);
    /// host_page_size() returns the same kernel page size as a plain call.
    private let pageSize: UInt64

    public init() {
        hostPort = mach_host_self()
        var size: vm_size_t = 0
        pageSize = host_page_size(hostPort, &size) == KERN_SUCCESS ? UInt64(size) : 16_384
    }

    public func sample() throws -> RawMetricsSample {
        let (used, total) = try readMemory()
        let (received, sent) = try readNetworkTotals()
        return RawMetricsSample(
            uptime: Double(clock_gettime_nsec_np(CLOCK_MONOTONIC_RAW)) / 1e9,
            cpu: try readCPUTicks(),
            memoryUsedBytes: used,
            memoryTotalBytes: total,
            memoryPressure: readMemoryPressure(),
            networkBytesReceived: received,
            networkBytesSent: sent
        )
    }

    /// Kernel pressure level — what Activity Monitor's pressure gauge keys
    /// off, and a better "should I worry" signal than raw used bytes.
    /// Non-fatal: nil if the sysctl is unavailable.
    private func readMemoryPressure() -> MemoryPressureLevel? {
        var level: Int32 = 0
        var size = MemoryLayout<Int32>.size
        guard sysctlbyname("kern.memorystatus_vm_pressure_level", &level, &size, nil, 0) == 0 else {
            return nil
        }
        return MemoryPressureLevel(rawValue: Int(level))
    }

    private func readCPUTicks() throws -> CPUTicks {
        var info = host_cpu_load_info_data_t()
        var count = mach_msg_type_number_t(
            MemoryLayout<host_cpu_load_info_data_t>.size / MemoryLayout<integer_t>.size
        )
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics(hostPort, HOST_CPU_LOAD_INFO, $0, &count)
            }
        }
        guard result == KERN_SUCCESS else {
            throw MetricsError.machCall("host_statistics", result)
        }
        // cpu_ticks is indexed by CPU_STATE_USER/SYSTEM/IDLE/NICE (0...3).
        return CPUTicks(
            user: info.cpu_ticks.0,
            system: info.cpu_ticks.1,
            idle: info.cpu_ticks.2,
            nice: info.cpu_ticks.3
        )
    }

    private func readMemory() throws -> (used: UInt64, total: UInt64) {
        var vm = vm_statistics64_data_t()
        var count = mach_msg_type_number_t(
            MemoryLayout<vm_statistics64_data_t>.size / MemoryLayout<integer_t>.size
        )
        let result = withUnsafeMutablePointer(to: &vm) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(hostPort, HOST_VM_INFO64, $0, &count)
            }
        }
        guard result == KERN_SUCCESS else {
            throw MetricsError.machCall("host_statistics64", result)
        }

        var total: UInt64 = 0
        var size = MemoryLayout<UInt64>.size
        guard sysctlbyname("hw.memsize", &total, &size, nil, 0) == 0 else {
            throw MetricsError.sysctl("hw.memsize", errno)
        }

        // Activity-Monitor-style used = App Memory + Wired + Compressed,
        // where App Memory = internal - purgeable (purgeable can transiently
        // exceed internal, hence the saturating guard).
        let appPages = vm.internal_page_count >= vm.purgeable_count
            ? UInt64(vm.internal_page_count - vm.purgeable_count)
            : 0
        let usedPages = appPages + UInt64(vm.wire_count) + UInt64(vm.compressor_page_count)
        return (used: usedPages * pageSize, total: total)
    }

    private func readNetworkTotals() throws -> (received: UInt64, sent: UInt64) {
        // The NET_RT_IFLIST2 walk lives in EyrieCore (TrafficKit reads the
        // same counters per interface); the aggregate keeps the old behavior.
        NetworkInterfaceCounters.totals(of: try NetworkInterfaceCounters.read())
    }
}
