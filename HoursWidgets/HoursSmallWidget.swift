import WidgetKit
import SwiftUI
import AppIntents

// MARK: - Timeline entry
// All display data is precomputed at the entry's date so the static parts of
// the widget stay correct between reloads; the live parts (net timer while
// working, break timer on break) tick via Text(timerInterval:).

struct HoursEntry: TimelineEntry {
    let date: Date
    let state: TrackState
    /// Net worked on the calendar day of `date`, computed at `date`.
    let todayNet: TimeInterval
    /// Live shift clock-in (nil when clocked out).
    let clockIn: Date?
    /// Total break time of the live shift at `date`.
    let breakTotal: TimeInterval
    /// Start of the current break segment (nil unless on break).
    let breakStart: Date?
    /// Monday-based week-to-date net worked at `date`.
    let weekWorked: TimeInterval
    let goalMinutes: Double

    static let placeholder = HoursEntry(
        date: .now, state: .out, todayNet: 0, clockIn: nil,
        breakTotal: 0, breakStart: nil, weekWorked: 0, goalMinutes: 32.5 * 60
    )
}

// MARK: - Provider

struct HoursProvider: TimelineProvider {
    func placeholder(in context: Context) -> HoursEntry { .placeholder }

    func getSnapshot(in context: Context, completion: @escaping (HoursEntry) -> Void) {
        Task { @MainActor in
            completion(Self.makeEntries(at: [Date.now]).first ?? .placeholder)
        }
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<HoursEntry>) -> Void) {
        Task { @MainActor in
            let now = Date.now
            // Entries at now and every 5 minutes for the next hour; while a shift
            // is live, net/week totals keep growing, so each entry recomputes them
            // at its own date.
            let dates = stride(from: 0, through: 60, by: 5)
                .map { now.addingTimeInterval(TimeInterval($0) * 60) }
            completion(Timeline(entries: Self.makeEntries(at: dates), policy: .atEnd))
        }
    }

    /// Reads the shared store once, then evaluates the engine at each entry date.
    @MainActor
    private static func makeEntries(at dates: [Date]) -> [HoursEntry] {
        let store = TrackerStore.shared
        let all = store.allSnapshots
        let live = store.liveSnapshot
        let state = Engine.state(live: live)
        // Read the goal fresh from the App Group — the process-cached
        // AppSettings singleton can be stale in a long-lived widget process.
        let goalMinutes = (AppGroup.defaults.object(forKey: "weeklyGoalHours") as? Double ?? 32.5) * 60
        return dates.map { at in
            HoursEntry(
                date: at,
                state: state,
                todayNet: Engine.dayTotals(on: at, sessions: all, at: at).work,
                clockIn: live?.clockIn,
                breakTotal: live.map { Engine.breakDuration($0, at: at) } ?? 0,
                breakStart: state == .onBreak ? live?.segments.last?.start : nil,
                weekWorked: Engine.weekWorked(sessions: all, at: at),
                goalMinutes: goalMinutes
            )
        }
    }
}

// MARK: - Widget

struct HoursSmallWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "HoursSmallWidget", provider: HoursProvider()) { entry in
            HoursSmallWidgetView(entry: entry)
        }
        .configurationDisplayName("Hours")
        .description("Clock in, take breaks and clock out without opening the app.")
        .supportedFamilies([.systemSmall])
    }
}

// MARK: - View (mockup .hw)

struct HoursSmallWidgetView: View {
    let entry: HoursEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                Text("HOURS")
                    .font(.system(size: 10.5, weight: .bold))
                    .kerning(0.6)
                    .foregroundStyle(Theme.secondary)
                Spacer(minLength: 4)
                Text(stateLabel)
                    .font(.system(size: 10.5))
                    .foregroundStyle(Theme.secondary)
                    .lineLimit(1)
                    .invalidatableContent()
            }

            bigLine
                .padding(.top, 1)
                .invalidatableContent()

            subLine
                .font(.system(size: 10.5, weight: .medium))
                .foregroundStyle(Theme.secondary)
                .lineLimit(1)
                .invalidatableContent()

            Spacer(minLength: 4)

            buttonsRow
                .invalidatableContent()

            miniWeekBar
                .padding(.top, 8)
                .invalidatableContent()
        }
        .containerBackground(Theme.card, for: .widget)
    }

    private var stateLabel: String {
        switch entry.state {
        case .out: return "○ Off the clock"
        case .working: return "● Working"
        case .onBreak: return "Ⅱ On break"
        }
    }

    /// Today's net hours; ticks live while working (anchor = date − net at date).
    /// Once the shift crosses midnight the day of `entry.date` accrues nothing
    /// (a shift belongs to its clock-in day), so ticking would restart from
    /// 0:00 at every entry — show the static total instead.
    private var accruesToEntryDay: Bool {
        guard entry.state == .working, let clockIn = entry.clockIn else { return false }
        return TimeMath.dayKey(clockIn) == TimeMath.dayKey(entry.date)
    }

    private var bigLine: some View {
        Group {
            if accruesToEntryDay {
                Text(timerInterval: entry.date.addingTimeInterval(-entry.todayNet)...Date.distantFuture,
                     countsDown: false)
            } else {
                Text(Fmt.dur(entry.todayNet))
            }
        }
        .font(.system(size: 21, weight: .heavy))
        .monospacedDigit()
        .foregroundStyle(Theme.label)
        .lineLimit(1)
        .minimumScaleFactor(0.6)
        .multilineTextAlignment(.leading)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var subLine: Text {
        switch entry.state {
        case .out:
            return Text("today so far")
        case .working:
            var s = "since \(Fmt.time(entry.clockIn ?? entry.date))"
            if entry.breakTotal > 0 { s += " · breaks \(Fmt.dur(entry.breakTotal))" }
            return Text(s)
        case .onBreak:
            return Text("break ")
                + Text(timerInterval: (entry.breakStart ?? entry.date)...Date.distantFuture,
                       countsDown: false)
        }
    }

    @ViewBuilder private var buttonsRow: some View {
        HStack(spacing: 6) {
            switch entry.state {
            case .out:
                WidgetPill(label: "▶ Start", bg: Theme.greenT, fg: Theme.greenD, intent: ClockInIntent())
            case .working:
                WidgetPill(label: "Ⅱ Break", bg: Theme.amberT, fg: Theme.amberD, intent: StartBreakIntent())
                WidgetPill(label: "■ Stop", bg: Theme.redT, fg: Theme.redD, intent: ClockOutIntent())
            case .onBreak:
                WidgetPill(label: "▶ Resume", bg: Theme.greenT, fg: Theme.greenD, intent: ResumeIntent())
                WidgetPill(label: "■ Stop", bg: Theme.redT, fg: Theme.redD, intent: ClockOutIntent())
            }
        }
    }

    private var weekProgress: Double {
        let goal = entry.goalMinutes * 60
        guard goal > 0 else { return 0 }
        return min(1, entry.weekWorked / goal)
    }

    private var miniWeekBar: some View {
        VStack(spacing: 4) {
            HStack {
                Text("This week")
                Spacer(minLength: 4)
                Text(Fmt.dur(entry.weekWorked) + " / " + Fmt.hm(Int(entry.goalMinutes.rounded())))
            }
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(Theme.tertiary)
            .lineLimit(1)
            .minimumScaleFactor(0.8)

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Theme.inset)
                    Capsule().fill(Theme.green)
                        .frame(width: max(0, geo.size.width * weekProgress))
                }
            }
            .frame(height: 5)
        }
    }
}

// MARK: - Intent button pill

private struct WidgetPill<I: AppIntent>: View {
    let label: String
    let bg: Color
    let fg: Color
    let intent: I

    var body: some View {
        Button(intent: intent) {
            Text(label)
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(fg)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                .background(bg, in: RoundedRectangle(cornerRadius: 11, style: .continuous))
                .contentShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}
