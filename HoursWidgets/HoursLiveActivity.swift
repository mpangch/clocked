import SwiftUI
import WidgetKit
import AppIntents
#if canImport(ActivityKit)
import ActivityKit

// MARK: - Live Activity (mockup .la — lock-screen presentation on iPhone 13)

struct HoursLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: HoursActivityAttributes.self) { context in
            HoursLockScreenView(state: context.state)
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
                    HoursActivityTimer(state: context.state)
                        .font(.system(size: 20, weight: .heavy))
                        .monospacedDigit()
                        .lineLimit(1)
                        .multilineTextAlignment(.trailing)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    HoursActivityButtons(isOnBreak: context.state.isOnBreak)
                }
            } compactLeading: {
                Text("H")
                    .font(.system(size: 14, weight: .heavy))
                    .foregroundStyle(Theme.green)
            } compactTrailing: {
                HoursActivityTimer(state: context.state)
                    .monospacedDigit()
                    .lineLimit(1)
                    .frame(maxWidth: 60)
                    .multilineTextAlignment(.trailing)
            } minimal: {
                Text("H")
                    .font(.system(size: 14, weight: .heavy))
                    .foregroundStyle(Theme.green)
            }
        }
    }
}

// MARK: - Lock screen view

struct HoursLockScreenView: View {
    let state: HoursActivityAttributes.ContentState

    var body: some View {
        VStack(spacing: 12) {
            HStack(spacing: 10) {
                Text("H")
                    .font(.system(size: 16, weight: .heavy))
                    .foregroundStyle(.white)
                    .frame(width: 30, height: 30)
                    .background(Theme.green, in: RoundedRectangle(cornerRadius: 8, style: .continuous))

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

                HoursActivityTimer(state: state)
                    .font(.system(size: 26, weight: .heavy))
                    .monospacedDigit()
                    .foregroundStyle(Theme.label)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    .multilineTextAlignment(.trailing)
            }
            HoursActivityButtons(isOnBreak: state.isOnBreak)
        }
        .padding(14)
    }

    private var sub: String {
        state.isOnBreak
            ? "unpaid · worked " + Fmt.dur(state.netWorkedAtBreakStart)
            : "since " + Fmt.time(state.clockIn)
    }
}

// MARK: - Shared pieces

/// Working → live net-hours timer from netAnchor; on break → break timer (amberD).
struct HoursActivityTimer: View {
    let state: HoursActivityAttributes.ContentState

    var body: some View {
        if state.isOnBreak {
            Text(timerInterval: (state.breakStart ?? .now)...Date.distantFuture, countsDown: false)
                .foregroundStyle(Theme.amberD)
        } else {
            Text(timerInterval: state.netAnchor...Date.distantFuture, countsDown: false)
        }
    }
}

struct HoursActivityButtons: View {
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
