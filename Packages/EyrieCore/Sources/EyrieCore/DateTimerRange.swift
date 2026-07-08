import Foundation

public extension Date {
    /// Range for SwiftUI's `Text(timerInterval:)` that can never be reversed:
    /// an end date that already passed (e.g. one render frame after a timer
    /// expires) collapses to an empty range instead of trapping.
    static func timerRange(until end: Date, now: Date = .now) -> ClosedRange<Date> {
        now...max(end, now)
    }
}
