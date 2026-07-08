import Foundation
import Observation
import os

/// One completed focus session.
public struct FocusSession: Codable, Sendable, Identifiable, Equatable {
    public let id: UUID
    public let startDate: Date
    public let endDate: Date
    /// Effective focus time in seconds, excluding pauses.
    public let duration: TimeInterval

    public init(id: UUID = UUID(), startDate: Date, endDate: Date, duration: TimeInterval) {
        self.id = id
        self.startDate = startDate
        self.endDate = endDate
        self.duration = duration
    }
}

/// Aggregated totals for one calendar day.
public struct DailyFocusTotal: Identifiable, Sendable, Equatable {
    public let day: Date
    public let sessionCount: Int
    public let focusSeconds: TimeInterval
    public var id: Date { day }
}

/// Loads, appends, prunes, and aggregates focus session history.
/// Persisted as JSON at ~/Library/Application Support/Eyrie/focus-history.json.
@MainActor
@Observable
public final class FocusHistoryStore {
    public private(set) var sessions: [FocusSession] = []

    /// Days of history retained; older sessions are pruned on load and append.
    public static let retentionDays = 365

    @ObservationIgnored private let fileURL: URL
    @ObservationIgnored private let calendar = Calendar.current
    @ObservationIgnored private let logger = Logger(subsystem: "com.erkanerturk.eyrie", category: "FocusHistory")

    /// `fileURL` is injectable for tests; defaults to the Application Support location.
    public init(fileURL: URL? = nil) {
        self.fileURL = fileURL ?? FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appending(path: "Eyrie/focus-history.json")
        load()
    }

    // MARK: Mutation

    public func record(_ session: FocusSession) {
        sessions.append(session)
        prune()
        save()
    }

    // MARK: Aggregation

    /// Sessions that finished today.
    public var completedToday: Int {
        sessions.count { calendar.isDateInToday($0.endDate) }
    }

    public var totalSessions: Int { sessions.count }

    public var totalFocusSeconds: TimeInterval {
        sessions.reduce(0) { $0 + $1.duration }
    }

    public func sessionCount(since date: Date) -> Int {
        sessions.count { $0.endDate >= date }
    }

    public func focusSeconds(since date: Date) -> TimeInterval {
        sessions.filter { $0.endDate >= date }.reduce(0) { $0 + $1.duration }
    }

    /// One entry per day for the last `days` days, oldest first, including
    /// zero-filled days so the bar chart keeps a stable x-axis.
    public func dailyTotals(days: Int, now: Date = .now) -> [DailyFocusTotal] {
        let today = calendar.startOfDay(for: now)
        var buckets: [Date: (count: Int, seconds: TimeInterval)] = [:]
        for session in sessions {
            let day = calendar.startOfDay(for: session.endDate)
            buckets[day, default: (0, 0)].count += 1
            buckets[day, default: (0, 0)].seconds += session.duration
        }
        return (0..<days).reversed().compactMap { offset in
            guard let day = calendar.date(byAdding: .day, value: -offset, to: today) else { return nil }
            let bucket = buckets[day] ?? (0, 0)
            return DailyFocusTotal(day: day, sessionCount: bucket.count, focusSeconds: bucket.seconds)
        }
    }

    // MARK: Persistence

    private struct HistoryFile: Codable {
        var version: Int
        var sessions: [FocusSession]
    }

    private func load() {
        guard let data = try? Data(contentsOf: fileURL) else { return }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        do {
            sessions = try decoder.decode(HistoryFile.self, from: data).sessions
            prune()
        } catch {
            logger.error("Failed to decode focus history, starting empty: \(error)")
        }
    }

    private func save() {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        do {
            let data = try encoder.encode(HistoryFile(version: 1, sessions: sessions))
            try FileManager.default.createDirectory(
                at: fileURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try data.write(to: fileURL, options: .atomic)
        } catch {
            logger.error("Failed to save focus history: \(error)")
        }
    }

    private func prune(now: Date = .now) {
        guard let cutoff = calendar.date(byAdding: .day, value: -Self.retentionDays, to: now) else { return }
        sessions.removeAll { $0.endDate < cutoff }
    }
}
