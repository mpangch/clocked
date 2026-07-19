import SwiftUI
import SwiftData
import Charts

// MARK: - Review tab (mockup: renderReview)

struct ReviewView: View {
    @Environment(AppModel.self) private var model
    /// Present so SwiftData changes (clock events, edits, deletes, adds) re-render this view.
    @Query(sort: \Shift.clockIn) private var shifts: [Shift]

    private var store: TrackerStore { .shared }

    var body: some View {
        TimelineView(.periodic(from: .now, by: 30)) { timeline in
            content(now: timeline.date)
        }
    }

    // MARK: main layout

    @ViewBuilder
    private func content(now: Date) -> some View {
        @Bindable var model = model
        let (from, to) = Engine.periodRange(mode: model.reviewMode, offset: model.reviewOffset, today: now)
        // Only the visible period leaves the database — lifetime history
        // stays in SQLite no matter how many years accumulate.
        let all = store.allSnapshots(from: from, to: to)
        let byDay = Engine.totalsByDay(sessions: all, at: now)
        let tot = Engine.rangeTotals(from: from, to: to, sessions: all, at: now)
        let goal = Engine.periodGoal(mode: model.reviewMode, from: from, to: to,
                                     goalMinutes: AppSettings.shared.weeklyGoalMinutes)

        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text("Review")
                    .font(.system(size: 32, weight: .heavy))
                    .foregroundStyle(Theme.label)
                    .padding(.top, 6)
                    .padding(.horizontal, 2)
                    .padding(.bottom, 2)

                Picker("Period", selection: $model.reviewMode) {
                    ForEach(ReviewMode.allCases, id: \.self) { mode in
                        Text(mode.title).tag(mode)
                    }
                }
                .pickerStyle(.segmented)

                periodNav(from: from, to: to)
                statRow(tot)
                goalProgressCard(worked: tot.paid, goal: goal)
                chartCard(from: from, to: to, all: all, byDay: byDay, now: now)
                goalSettingCard
                daysHeader(from: from, to: to, now: now)
                dayList(from: from, to: to, byDay: byDay, now: now)
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 28)
        }
        .background(Theme.bg.ignoresSafeArea())
        .onChange(of: model.reviewMode) { model.reviewOffset = 0 }
    }

    // MARK: period navigation (mockup: periodNav / revNav)

    private func periodNav(from: Date, to: Date) -> some View {
        let (label, sub) = periodLabels(from: from, to: to)
        return HStack {
            navButton("‹", disabled: false) { model.reviewOffset -= 1 }
            Spacer()
            VStack(spacing: 1) {
                Text(label)
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(Theme.label)
                Text(sub)
                    .font(.system(size: 12.5, weight: .medium))
                    .foregroundStyle(Theme.secondary)
            }
            Spacer()
            navButton("›", disabled: model.reviewOffset == 0) {
                model.reviewOffset = min(0, model.reviewOffset + 1)
            }
        }
        .padding(.horizontal, 4)
    }

    private func navButton(_ symbol: String, disabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(symbol)
                .font(.system(size: 19, weight: .bold))
                .foregroundStyle(Theme.blue)
                .frame(width: 34, height: 34)
                .background(Theme.card)
                .clipShape(Circle())
                .shadow(color: .black.opacity(0.08), radius: 2, y: 1)
        }
        .buttonStyle(.plain)
        .disabled(disabled)
        .opacity(disabled ? 0.3 : 1)
    }

    private func periodLabels(from: Date, to: Date) -> (label: String, sub: String) {
        let rangeStr = Fmt.dateShort(from) + " – " + Fmt.dateShort(TimeMath.addDays(to, -1))
        switch model.reviewMode {
        case .week:
            return model.reviewOffset == 0 ? ("This Week", rangeStr) : (rangeStr, "Week")
        case .biweek:
            return (rangeStr, model.reviewOffset == 0 ? "Current 2-week period" : "2-week period")
        case .month:
            let c = Calendar.current.dateComponents([.month, .year], from: from)
            let label = Fmt.monthsShort[c.month! - 1] + " " + String(c.year!)
            return (label, model.reviewOffset == 0 ? "This month" : "Month")
        }
    }

    // MARK: stat cards (mockup: revStats)

    private func statRow(_ tot: RangeTotals) -> some View {
        HStack(spacing: 10) {
            statCard(Fmt.dur(tot.paid), "Paid", Theme.greenD)
            statCard(Fmt.dur(tot.brk), "Breaks", Theme.amberD)
            statCard(tot.daysWithPaid > 0 ? Fmt.dur(tot.paid / Double(tot.daysWithPaid)) : "—",
                     "Avg / day", Theme.label)
        }
    }

    private func statCard(_ value: String, _ label: String, _ color: Color) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(value)
                .font(.system(size: 21, weight: .heavy))
                .monospacedDigit()
                .foregroundStyle(color)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(label.uppercased())
                .font(.system(size: 11.5, weight: .semibold))
                .kerning(0.4)
                .foregroundStyle(Theme.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 12)
        .padding(.horizontal, 14)
        .background(Theme.card)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    // MARK: goal progress (mockup: goalProgressCard)

    private func goalProgressCard(worked: TimeInterval, goal: TimeInterval) -> some View {
        let title: String
        switch model.reviewMode {
        case .week: title = "Weekly goal"
        case .biweek: title = "2-week goal (×2)"
        case .month: title = "Monthly goal (pro-rated)"
        }
        let need = Engine.goalNeed(worked: worked, goal: goal)
        return Card(title: title) {
            HStack(alignment: .firstTextBaseline) {
                (Text(Fmt.dur(worked))
                    .font(.system(size: 22, weight: .heavy))
                    .foregroundStyle(Theme.label)
                 + Text(" / " + Fmt.dur(goal))
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Theme.secondary))
                    .monospacedDigit()
                Spacer(minLength: 12)
                Text(.init(need.text))
                    .font(.system(size: 13.5, weight: .semibold))
                    .foregroundStyle(Theme.secondary)
                    .multilineTextAlignment(.trailing)
            }
            ProgressBar(progress: goal > 0 ? worked / goal : 0)
        }
    }

    // MARK: chart (mockup: chart columns)

    private struct ChartColumn: Identifiable {
        let idx: Int
        let work: TimeInterval
        let brk: TimeInterval
        let label: String
        let isToday: Bool
        var id: Int { idx }
    }

    private func chartColumns(from: Date, to: Date, all: [SessionSnapshot], byDay: [String: DayTotals], now: Date) -> [ChartColumn] {
        let cal = Calendar.current
        let todayKey = TimeMath.dayKey(now)
        var cols: [ChartColumn] = []
        if model.reviewMode != .month {
            let letters = Array("MTWTFSS")     // Mon-first
            for (i, d) in TimeMath.eachDay(from: from, to: to).enumerated() {
                let t = byDay[TimeMath.dayKey(d)] ?? DayTotals()
                let label = model.reviewMode == .week
                    ? String(letters[(TimeMath.jsWeekday(d) + 6) % 7])
                    : String(cal.component(.day, from: d))
                cols.append(ChartColumn(idx: i, work: t.work, brk: t.brk,
                                        label: label, isToday: TimeMath.dayKey(d) == todayKey))
            }
        } else {
            // One bar per Monday-based week, clipped to the month.
            var ws = TimeMath.monday(of: from)
            var i = 0
            while ws < to {
                let we = TimeMath.addDays(ws, 7)
                let f2 = max(ws, from)
                let t2 = min(we, to)
                let t = Engine.rangeTotals(from: f2, to: t2, sessions: all, at: now)
                let label = "\(cal.component(.day, from: f2))–\(cal.component(.day, from: TimeMath.addDays(t2, -1)))"
                cols.append(ChartColumn(idx: i, work: t.work, brk: t.brk, label: label,
                                        isToday: now >= f2 && now < t2))
                ws = we
                i += 1
            }
        }
        return cols
    }

    private func chartCard(from: Date, to: Date, all: [SessionSnapshot], byDay: [String: DayTotals], now: Date) -> some View {
        let cols = chartColumns(from: from, to: to, all: all, byDay: byDay, now: now)
        // mockup: maxV = Math.max(8 * HOUR, ...cols.map(c => c.w + c.b)) — in hours here.
        let maxHours = max(8.0, cols.map { ($0.work + $0.brk) / TimeMath.hour }.max() ?? 0)
        return Card(title: model.reviewMode == .month ? "Hours per week" : "Hours per day") {
            Chart {
                ForEach(cols) { col in
                    BarMark(
                        x: .value("Period", String(col.idx)),
                        y: .value("Worked", col.work / TimeMath.hour)
                    )
                    .foregroundStyle(col.isToday ? Theme.greenD : Theme.green)
                    .cornerRadius(3)

                    BarMark(
                        x: .value("Period", String(col.idx)),
                        y: .value("Break", col.brk / TimeMath.hour)
                    )
                    .foregroundStyle(Theme.amber.opacity(0.85))
                    .cornerRadius(3)

                    if col.work + col.brk > 0 {
                        PointMark(
                            x: .value("Period", String(col.idx)),
                            y: .value("Total", (col.work + col.brk) / TimeMath.hour)
                        )
                        .symbolSize(0)
                        .opacity(0)
                        .annotation(position: .top, spacing: 2) {
                            Text(Fmt.h1(col.work + col.brk))
                                .font(.system(size: 10, weight: .semibold))
                                .monospacedDigit()
                                .foregroundStyle(Theme.tertiary)
                        }
                    }
                }
            }
            .chartXScale(domain: cols.map { String($0.idx) })
            .chartYScale(domain: 0...maxHours)
            .chartYAxis(.hidden)
            .chartXAxis {
                AxisMarks(values: cols.map { String($0.idx) }) { value in
                    AxisValueLabel {
                        if let s = value.as(String.self), let i = Int(s), i < cols.count {
                            Text(cols[i].label)
                                .font(.system(size: 10.5, weight: cols[i].isToday ? .heavy : .semibold))
                                .foregroundStyle(cols[i].isToday ? Theme.label : Theme.secondary)
                        }
                    }
                }
            }
            .chartLegend(.hidden)
            .frame(height: 132)

            HStack(spacing: 14) {
                legendItem(Theme.green, "Worked")
                legendItem(Theme.amber, "Paid break")
            }
            .padding(.top, 2)
        }
    }

    private func legendItem(_ color: Color, _ label: String) -> some View {
        HStack(spacing: 5) {
            RoundedRectangle(cornerRadius: 3, style: .continuous)
                .fill(color)
                .frame(width: 9, height: 9)
            Text(label)
                .font(.system(size: 11.5, weight: .medium))
                .foregroundStyle(Theme.secondary)
        }
    }

    // MARK: weekly-goal setting (mockup: goalCard / stepGoal)

    private var goalSettingCard: some View {
        Card(title: "Weekly goal") {
            StepperRow(
                label: "Target hours / week",
                sublabel: "drives week, 2-week and month targets",
                value: Fmt.goalHours(AppSettings.shared.weeklyGoalHours),
                onMinus: { stepGoal(-1) },
                onPlus: { stepGoal(1) }
            )
        }
    }

    private func stepGoal(_ dir: Int) {
        AppSettings.shared.weeklyGoalHours =
            Engine.stepGoal(AppSettings.shared.weeklyGoalMinutes, dir: dir) / 60
    }

    // MARK: days header (mockup: Days + Add entry / Export CSV)

    private func daysHeader(from: Date, to: Date, now: Date) -> some View {
        HStack(spacing: 8) {
            Text("DAYS")
                .font(.system(size: 13, weight: .semibold))
                .kerning(0.6)
                .foregroundStyle(Theme.secondary)
            Spacer()
            MiniButton(title: "＋ Add entry") { model.activeSheet = .addEntry }
            MiniButton(title: "Export CSV") { exportCSV(from: from, to: to, now: now) }
        }
        .padding(.horizontal, 4)
        .padding(.top, 4)
    }

    private func exportCSV(from: Date, to: Date, now: Date) {
        let history = store.historySnapshots(from: from, to: to)
        let live = store.liveSnapshot
        let text = Engine.csv(history: history, live: live, from: from, to: to, at: now)
        var n = history.filter { $0.clockIn >= from && $0.clockIn < to }.count
        if let live, live.clockIn >= from, live.clockIn < to { n += 1 }
        let rangeStr = Fmt.dateShort(from) + " – " + Fmt.dateShort(TimeMath.addDays(to, -1))
        let subtitle = "\(rangeStr) · \(n) shift\(n == 1 ? "" : "s")"
        model.activeSheet = .csv(text: text, subtitle: subtitle)
    }

    // MARK: day list (mockup: dayList)

    private struct DayEntry: Identifiable {
        let day: Date
        let totals: DayTotals
        var id: Date { day }
    }

    @ViewBuilder
    private func dayList(from: Date, to: Date, byDay: [String: DayTotals], now: Date) -> some View {
        let entries: [DayEntry] = TimeMath.eachDay(from: from, to: to).reversed().compactMap { d in
            guard let t = byDay[TimeMath.dayKey(d)], t.sessionCount > 0 else { return nil }
            return DayEntry(day: d, totals: t)
        }
        if entries.isEmpty {
            Text("No time tracked in this period")
                .font(.system(size: 15))
                .foregroundStyle(Theme.tertiary)
                .frame(maxWidth: .infinity)
                .padding(16)
                .background(Theme.card)
                .clipShape(RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))
        } else {
            VStack(spacing: 8) {
                ForEach(entries) { entry in
                    dayRow(entry, now: now)
                }
            }
        }
    }

    private func dayRow(_ entry: DayEntry, now: Date) -> some View {
        let t = entry.totals
        let isToday = TimeMath.dayKey(entry.day) == TimeMath.dayKey(now)
        var sub = ""
        if let first = t.first, let last = t.last {
            sub = Fmt.time(first) + " – "
                + (isToday && store.liveSnapshot != nil ? "now" : Fmt.time(last))
        }
        if t.sessionCount > 1 { sub += " · \(t.sessionCount) sessions" }
        return Button {
            model.activeSheet = .dayDetail(entry.day)
        } label: {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(isToday ? "Today" : Fmt.weekdayShort(entry.day) + ", " + Fmt.dateShort(entry.day))
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(Theme.label)
                    Text(sub)
                        .font(.system(size: 12.5))
                        .foregroundStyle(Theme.secondary)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 1) {
                    Text(Fmt.dur(t.paid))
                        .font(.system(size: 17, weight: .heavy))
                        .monospacedDigit()
                        .foregroundStyle(Theme.label)
                    if t.brk > 0 {
                        Text(Fmt.dur(t.brk) + " break")
                            .font(.system(size: 11.5, weight: .semibold))
                            .foregroundStyle(Theme.amberD)
                    }
                }
                Text("›")
                    .font(.system(size: 17))
                    .foregroundStyle(Theme.tertiary)
            }
            .padding(.vertical, 13)
            .padding(.horizontal, 15)
            .background(Theme.card)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}
