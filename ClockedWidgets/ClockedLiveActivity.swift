import SwiftUI
import WidgetKit
import AppIntents
#if canImport(ActivityKit)
import ActivityKit

// MARK: - Live Activity (mockup .la — lock-screen presentation on iPhone 13)

struct ClockedLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: ClockedActivityAttributes.self) { context in
            ClockedLockScreenView(state: context.state)
                .activityBackgroundTint(Color(hex: 0xFCFCFE).opacity(0.93))
                .activitySystemActionForegroundColor(Theme.label)
        } dynamicIsland: { context in
            // iPhone 13 has no Dynamic Island — iOS shows a status-bar time pill
            // instead. This minimal implementation only satisfies the API.
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Text(context.state.isOnBreak ? "ON BREAK" : "WORKING")
                        .font(.system(size: 12, weight: .bold))
                        .kerning(0.8)
                        .foregroundStyle(context.state.isOnBreak ? Theme.amberD : Theme.greenD)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    ClockedActivityTimer(state: context.state)
                        .font(.system(size: 20, weight: .heavy))
                        .monospacedDigit()
                        .lineLimit(1)
                        .multilineTextAlignment(.trailing)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    ClockedActivityButtons(isOnBreak: context.state.isOnBreak)
                }
            } compactLeading: {
                RingMark(isOnBreak: context.state.isOnBreak, lineWidth: 3)
                    .frame(width: 16, height: 16)
            } compactTrailing: {
                ClockedActivityTimer(state: context.state)
                    .monospacedDigit()
                    .lineLimit(1)
                    .frame(maxWidth: 60)
                    .multilineTextAlignment(.trailing)
            } minimal: {
                RingMark(isOnBreak: context.state.isOnBreak, lineWidth: 3)
                    .frame(width: 16, height: 16)
            }
        }
    }
}

// MARK: - App mark
// The icon is a progress ring, not a letter — so the Live Activity wears the
// same face. It also carries state: green while working, amber on break.

struct RingMark: View {
    var isOnBreak: Bool
    var lineWidth: CGFloat = 4
    /// Fraction of the ring drawn — matches the icon's three-quarter arc.
    private let trim: CGFloat = 0.72

    var body: some View {
        ZStack {
            Circle()
                .stroke(color.opacity(0.25), lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: trim)
                .stroke(color, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
    }

    private var color: Color { isOnBreak ? Theme.amber : Theme.green }
}

private struct AppMark: View {
    var isOnBreak: Bool

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.white.opacity(0.35), lineWidth: 3.5)
            Circle()
                .trim(from: 0, to: 0.72)
                .stroke(.white, style: StrokeStyle(lineWidth: 3.5, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
        .frame(width: 17, height: 17)
        .frame(width: 30, height: 30)
        .background(isOnBreak ? Theme.amber : Theme.green,
                    in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

// MARK: - Lock screen view

struct ClockedLockScreenView: View {
    let state: ClockedActivityAttributes.ContentState

    var body: some View {
        VStack(spacing: 12) {
            HStack(spacing: 10) {
                AppMark(isOnBreak: state.isOnBreak)

                VStack(alignment: .leading, spacing: 1) {
                    Text(state.isOnBreak ? "ON BREAK" : "WORKING")
                        .font(.system(size: 12, weight: .bold))
                        .kerning(0.8)
                        .foregroundStyle(state.isOnBreak ? Theme.amberD : Theme.greenD)
                    Text(sub)
                        .font(.system(size: 11.5))
                        .foregroundStyle(Theme.secondary)
                        .lineLimit(1)
                }

                Spacer(minLength: 8)

                ClockedActivityTimer(state: state)
                    .font(.system(size: 26, weight: .heavy))
                    .monospacedDigit()
                    .foregroundStyle(Theme.label)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    .multilineTextAlignment(.trailing)
            }
            ClockedActivityButtons(isOnBreak: state.isOnBreak)
        }
        .padding(14)
    }

    private var sub: String {
        state.isOnBreak
            ? "paid break · since " + Fmt.time(state.clockIn)
            : "since " + Fmt.time(state.clockIn)
    }
}

// MARK: - Shared pieces

/// Working → live net-hours timer from netAnchor; on break → break timer (amberD).
struct ClockedActivityTimer: View {
    let state: ClockedActivityAttributes.ContentState

    var body: some View {
        if state.isOnBreak {
            Text(timerInterval: (state.breakStart ?? .now)...Date.distantFuture, countsDown: false)
                .foregroundStyle(Theme.amberD)
        } else {
            Text(timerInterval: state.netAnchor...Date.distantFuture, countsDown: false)
        }
    }
}

struct ClockedActivityButtons: View {
    let isOnBreak: Bool

    var body: some View {
        HStack(spacing: 8) {
            if isOnBreak {
                ActivityPill(label: "▶ Resume", bg: Theme.green, fg: .white, intent: ResumeIntent())
            } else {
                ActivityPill(label: "Ⅱ Break", bg: Theme.amberT, fg: Theme.amberD, intent: StartBreakIntent())
            }
            ActivityPill(label: "■ Stop", bg: Theme.redT, fg: Theme.redD, intent: ClockOutIntent())
        }
    }
}

private struct ActivityPill<I: AppIntent>: View {
    let label: String
    let bg: Color
    let fg: Color
    let intent: I

    var body: some View {
        Button(intent: intent) {
            Text(label)
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(fg)
                .lineLimit(1)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 11)
                .background(bg, in: RoundedRectangle(cornerRadius: 13, style: .continuous))
                .contentShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}
#endif
