import SwiftUI

/// The app-wide vocabulary for "how is this doing". Every module speaks it, so
/// a warning looks the same whether it comes from memory pressure, latency or
/// an open Wi-Fi network.
public enum StatusTone: Sendable, Equatable, Comparable {
    /// Nothing to report — healthy, or simply not applicable.
    case normal
    /// Worth noticing, not urgent.
    case caution
    /// Actually wrong; the user should act.
    case critical
    /// Present but switched off / disconnected — greyed, never alarming.
    case inactive

    public var color: Color {
        switch self {
        case .normal: .green
        case .caution: .orange
        case .critical: .red
        case .inactive: .secondary
        }
    }

    /// Ranks by urgency so findings and badges can sort worst-first.
    /// `inactive` is the least urgent — it is a statement, not a problem.
    public var severity: Int {
        switch self {
        case .inactive: 0
        case .normal: 1
        case .caution: 2
        case .critical: 3
        }
    }

    public static func < (lhs: StatusTone, rhs: StatusTone) -> Bool {
        lhs.severity < rhs.severity
    }
}

/// The 6 pt dot used across panels to carry a `StatusTone`. Keeping the state
/// in the dot lets values stay neutral and monospaced.
public struct StatusDot: View {
    public var tone: StatusTone
    public var diameter: CGFloat

    public init(_ tone: StatusTone, diameter: CGFloat = 6) {
        self.tone = tone
        self.diameter = diameter
    }

    public var body: some View {
        Circle()
            .fill(tone.color)
            .frame(width: diameter, height: diameter)
    }
}
