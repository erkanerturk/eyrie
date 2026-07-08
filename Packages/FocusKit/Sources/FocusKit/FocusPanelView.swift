import SwiftUI
import EyrieCore

struct FocusPanelView: View {
    @Bindable var module: FocusModule

    var body: some View {
        VStack(spacing: 10) {
            if let pending = module.pendingPhase {
                pendingState(pending)
            } else if module.isActive {
                activeSession
            } else {
                idleState
            }
        }
        .frame(maxWidth: .infinity)
    }

    /// Shown when a phase has finished and the next one waits for the user.
    private func pendingState(_ next: FocusPhase) -> some View {
        VStack(spacing: 8) {
            Text(next == .focus ? "Break finished" : "Focus complete — \(module.completedToday) today")
                .font(.callout)
                .foregroundStyle(.secondary)
            HStack(spacing: 8) {
                Button {
                    module.startPending()
                } label: {
                    Label(startLabel(for: next), systemImage: "play.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.glassProminent)
                .controlSize(.large)

                GlassIconButton(symbolName: "stop.fill") {
                    module.stop()
                }
            }
        }
    }

    private func startLabel(for phase: FocusPhase) -> String {
        switch phase {
        case .focus: "Start Focus"
        case .shortBreak: "Start Short Break"
        case .longBreak: "Start Long Break"
        case .idle: "Start"
        }
    }

    private var idleState: some View {
        VStack(spacing: 8) {
            Button {
                module.start()
            } label: {
                Label("Start Focus", systemImage: "play.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.glassProminent)
            .controlSize(.large)

            if module.completedToday > 0 {
                Text("\(module.completedToday) focus session\(module.completedToday == 1 ? "" : "s") today")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var activeSession: some View {
        VStack(spacing: 10) {
            TimelineView(.periodic(from: .now, by: 1)) { context in
                ZStack {
                    Circle()
                        .stroke(.quaternary, lineWidth: 6)
                    Circle()
                        .trim(from: 0, to: module.progress(at: context.date))
                        .stroke(
                            module.phase.isBreak ? AnyShapeStyle(.green) : AnyShapeStyle(.tint),
                            style: StrokeStyle(lineWidth: 6, lineCap: .round)
                        )
                        .rotationEffect(.degrees(-90))
                        .animation(.linear(duration: 1), value: module.progress(at: context.date))

                    VStack(spacing: 2) {
                        remainingText
                            .font(.title2.weight(.semibold))
                            .monospacedDigit()
                        Text(module.phase.label)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .frame(width: 110, height: 110)

            HStack(spacing: 8) {
                GlassIconButton(symbolName: module.isPaused ? "play.fill" : "pause.fill") {
                    module.isPaused ? module.resume() : module.pause()
                }
                GlassIconButton(symbolName: "forward.end.fill") {
                    module.skip()
                }
                GlassIconButton(symbolName: "stop.fill") {
                    module.stop()
                }
            }
        }
    }

    @ViewBuilder
    private var remainingText: some View {
        if let remaining = module.pausedRemaining {
            Text(Duration.seconds(remaining), format: .time(pattern: .minuteSecond))
        } else if let end = module.phaseEndDate {
            Text(timerInterval: Date.timerRange(until: end), countsDown: true)
        } else {
            Text("--:--")
        }
    }
}
