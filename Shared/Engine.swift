import Foundation

// MARK: - Pure tracking/aggregation engine, ported 1:1 from the mockup's <script> block.
// All functions are pure; `at` plays the role of the mockup's now() for open segments.

enum Engine {
    static let editStepMinutes = 15
    static let geoStepMinutes = 5
    static let forgotClockOutThreshold: TimeInterval = 12 * TimeMath.hour

    // MARK: session math (mockup: segMs / sumSegs / state / liveNet / liveBreak)

    static func segDuration(_ seg: SegmentSnapshot, at: Date) -> TimeInterval {
        max(0, (seg.end ?? at).timeIntervalSince(seg.start))
    }

    static func workDuration(_ s: SessionSnapshot, at: Date) -> TimeInterval {
        s.segments.reduce(0) { $0 + ($1.isBreak ? 0 : segDuration($1, at: at)) }
    }

    static func breakDuration(_ s: SessionSnapshot, at: Date) -> TimeInterval {
        s.segments.reduce(0) { $0 + ($1.isBreak ? segDuration($1, at: at) : 0) }
    }

    static func breakCount(_ s: SessionSnapshot) -> Int {
        s.segments.filter(\.isBreak).count
    }

    /// Paid-breaks revision: breaks are paid, so paid time is the whole
    /// segment coverage (work + breaks). Unpaid pauses are clock-outs, whose
    /// gaps fall between sessions and are excluded naturally.
    static func paidDuration(_ s: SessionSnapshot, at: Date) -> TimeInterval {
        workDuration(s, at: at) + breakDuration(s, at: at)
    }

    static func state(live: SessionSnapshot?) -> TrackState {
        guard let live, let last = live.segments.last else { return .out }
        return last.isBreak ? .onBreak : .working
    }

    // MARK: day / range aggregation (mockup: sessionsOn / dayTotals / rangeTotals)

    /// Sessions belonging to the calendar day of `day` (a shift belongs to the day of its clockIn).
    static func sessions(on day: Date, in sessions: [SessionSnapshot], calendar: Calendar = .current) -> [SessionSnapshot] {
        let key = TimeMath.dayKey(day, calendar: calendar)
        return sessions.filter { TimeMath.dayKey($0.clockIn, calendar: calendar) == key }
    }

    static func dayTotals(on day: Date, sessions all: [SessionSnapshot], at: Date, calendar: Calendar = .current) -> DayTotals {
        var t = DayTotals()
        for s in sessions(on: day, in: all, calendar: calendar) {
            t.work += workDuration(s, at: at)
            t.brk += breakDuration(s, at: at)
            t.sessionCount += 1
            if t.first == nil || s.clockIn < t.first! { t.first = s.clockIn }
            let end = s.clockOut ?? at
            if t.last == nil || end > t.last! { t.last = end }
        }
        return t
    }

    /// One grouping pass over the sessions (mockup semantics: a session
    /// belongs to the day of its clockIn). Turns the D-days × N-sessions
    /// filter of per-day lookups into O(N + D) — the day list, chart, and
    /// range totals all share it.
    static func totalsByDay(sessions: [SessionSnapshot], at: Date, calendar: Calendar = .current) -> [String: DayTotals] {
        var byDay: [String: DayTotals] = [:]
        for s in sessions {
            let key = TimeMath.dayKey(s.clockIn, calendar: calendar)
            var t = byDay[key] ?? DayTotals()
            t.work += workDuration(s, at: at)
            t.brk += breakDuration(s, at: at)
            t.sessionCount += 1
            if t.first == nil || s.clockIn < t.first! { t.first = s.clockIn }
            let end = s.clockOut ?? at
            if t.last == nil || end > t.last! { t.last = end }
            byDay[key] = t
        }
        return byDay
    }

    /// Totals over day range [from, to)
    static func rangeTotals(from: Date, to: Date, sessions all: [SessionSnapshot], at: Date, calendar: Calendar = .current) -> RangeTotals {
        let byDay = totalsByDay(sessions: all, at: at, calendar: calendar)
        var t = RangeTotals()
        for d in TimeMath.eachDay(from: from, to: to, calendar: calendar) {
            guard let dt = byDay[TimeMath.dayKey(d, calendar: calendar)] else { continue }
            t.work += dt.work
            t.brk += dt.brk
            if dt.work > 0 { t.daysWithWork += 1 }
        }
        return t
    }

    /// mockup: weekWorked — Monday-based week containing `at`, includes the live session
    static func weekWorked(sessions: [SessionSnapshot], at: Date, calendar: Calendar = .current) -> TimeInterval {
        let m = TimeMath.monday(of: at, calendar: calendar)
        return rangeTotals(from: m, to: TimeMath.addDays(m, 7, calendar: calendar),
                           sessions: sessions, at: at, calendar: calendar).work
    }

    /// Paid hours this Monday-based week — what the goal cards and widget bar
    /// compare against the weekly goal under the paid-breaks revision.
    static func weekPaid(sessions: [SessionSnapshot], at: Date, calendar: Calendar = .current) -> TimeInterval {
        let m = TimeMath.monday(of: at, calendar: calendar)
        let t = rangeTotals(from: m, to: TimeMath.addDays(m, 7, calendar: calendar),
                            sessions: sessions, at: at, calendar: calendar)
        return t.paid
    }

    // MARK: learned behavior (mockup: statsFor, plus CLAUDE.md's rolling 8-week window)

    /// Per-weekday stats over completed sessions within the rolling 8-week window ending at `reference`.
    /// `weekday` uses JS convention: 0 = Sunday … 6 = Saturday.
    static func stats(forWeekday weekday: Int,
                      history: [SessionSnapshot],
                      reference: Date,
                      calendar: Calendar = .current) -> WeekdayStats? {
        let windowStart = TimeMath.addDays(TimeMath.startOfDay(reference, calendar: calendar), -56, calendar: calendar)
        let ss = history.filter {
            !$0.isLive
                && $0.clockIn >= windowStart
                && TimeMath.jsWeekday($0.clockIn, calendar: calendar) == weekday
        }
        guard !ss.isEmpty else { return nil }

        var net: TimeInterval = 0, brk: TimeInterval = 0
        var cnt = 0, startMin = 0
        var bStart = 0, bStartN = 0
        for s in ss {
            let at = s.clockOut ?? reference
            net += workDuration(s, at: at)
            brk += breakDuration(s, at: at)
            let breaks = s.segments.filter(\.isBreak)
            cnt += breaks.count
            startMin += TimeMath.minutesIntoDay(s.clockIn, calendar: calendar)
            if let firstBreak = breaks.first {
                bStart += TimeMath.minutesIntoDay(firstBreak.start, calendar: calendar)
                bStartN += 1
            }
        }
        let n = ss.count
        let avgBreaksPerShift = Double(cnt) / Double(n)
        let roundedBreakCount = TimeMath.jsRound(avgBreaksPerShift)
        return WeekdayStats(
            n: n,
            avgNetMin: TimeMath.jsRound(net / Double(n) / 60),
            avgBreakMin: TimeMath.jsRound(brk / Double(n) / 60),
            breakCount: roundedBreakCount,
            breakFreq: avgBreaksPerShift,
            avgStartMin: TimeMath.jsRound(Double(startMin) / Double(n)),
            typBreakStartMin: bStartN > 0 ? TimeMath.jsRound(Double(bStart) / Double(bStartN)) : nil,
            typBreakDurMin: cnt > 0
                ? TimeMath.jsRound(brk / Double(n) / 60 / Double(max(1, roundedBreakCount)))
                : 0
        )
    }

    /// mockup: suggestionText — returns markdown ("**bold**") or nil when no history.
    static func suggestionText(_ st: WeekdayStats?, weekday: Int) -> String? {
        guard let st else { return nil }
        var t = "\(Fmt.weekdays[weekday])s you usually work **\(Fmt.hm(TimeMath.round5(st.avgPaidMin)))**"
        if st.breakCount > 0, let typ = st.typBreakStartMin {
            let countWord = st.breakCount == 1 ? "a" : "\(st.breakCount)"
            t += ", with \(countWord) ~**\(Fmt.dur(Double(TimeMath.round5(st.typBreakDurMin)) * 60))** break around **\(Fmt.minToClock(typ))**"
        } else if st.breakFreq < 0.3 {
            t += ", usually without breaks"
        }
        return t + "."
    }

    /// mockup: usePlanSuggestion — fill the plan draft from stats
    static func planDraft(from st: WeekdayStats) -> PlanDraft {
        PlanDraft(
            workMin: TimeMath.round5(st.avgPaidMin),
            breakCount: st.breakCount,
            breakMin: st.breakCount > 0 ? TimeMath.round5(st.avgBreakMin) : 0
        )
    }

    // MARK: plan / ring / ETA (mockup: plannedWorkMs / etaText)

    /// Planned paid shift length: committed plan → learned weekday average →
    /// 7h fallback. Paid breaks live INSIDE this span (paid-breaks revision),
    /// so "hours on the clock" is literal.
    static func plannedWorkDuration(planWorkMin: Int?, stats: WeekdayStats?) -> TimeInterval {
        Double(planWorkMin ?? stats?.avgPaidMin ?? 7 * 60) * 60
    }

    /// mockup: etaText
    static func etaText(plannedWork: TimeInterval, netWorked: TimeInterval, at: Date, calendar: Calendar = .current) -> String {
        let remain = plannedWork - netWorked
        return remain > 0
            ? "done ~" + Fmt.time(at.addingTimeInterval(remain), calendar: calendar)
            : "planned hours complete"
    }

    static func ringProgress(netWorked: TimeInterval, plannedWork: TimeInterval) -> Double {
        // mockup setRing clamps net/planned to [0,1]; with planned == 0 the JS
        // division yields Infinity → clamps to a FULL ring once any net exists.
        guard plannedWork > 0 else { return netWorked > 0 ? 1 : 0 }
        return min(1, max(0, netWorked / plannedWork))
    }

    // MARK: break nudge (mockup: renderTrack nudge conditions)

    /// Nudge: working, not dismissed, no break yet this shift, weekday break frequency ≥ 0.5,
    /// and now within −20/+45 min of the typical break start.
    static func shouldShowBreakNudge(stats: WeekdayStats?,
                                     state: TrackState,
                                     nudgeDismissed: Bool,
                                     liveBreakCount: Int,
                                     at: Date,
                                     calendar: Calendar = .current) -> Bool {
        guard state == .working, !nudgeDismissed,
              let st = stats, let typ = st.typBreakStartMin,
              st.breakFreq >= 0.5, liveBreakCount == 0 else { return false }
        let nowMin = TimeMath.minutesIntoDay(at, calendar: calendar)
        return nowMin >= typ - 20 && nowMin <= typ + 45
    }

    /// mockup: forgot-to-clock-out banner after 12h on the clock
    static func forgotClockOut(live: SessionSnapshot?, at: Date) -> Bool {
        guard let live else { return false }
        return at.timeIntervalSince(live.clockIn) > forgotClockOutThreshold
    }

    // MARK: review periods (mockup: periodRange / periodGoalMs)

    /// [from, to) for the review period `offset` periods before the current one (offset ≤ 0).
    static func periodRange(mode: ReviewMode, offset: Int, today: Date, calendar: Calendar = .current) -> (from: Date, to: Date) {
        let t = TimeMath.startOfDay(today, calendar: calendar)
        switch mode {
        case .week:
            let s = TimeMath.addDays(TimeMath.monday(of: t, calendar: calendar), offset * 7, calendar: calendar)
            return (s, TimeMath.addDays(s, 7, calendar: calendar))
        case .biweek:
            // mockup: addDays(monday(t), -7 + off * 14) — anchored so the current period
            // spans last week + this week.
            let s = TimeMath.addDays(TimeMath.monday(of: t, calendar: calendar), -7 + offset * 14, calendar: calendar)
            return (s, TimeMath.addDays(s, 14, calendar: calendar))
        case .month:
            let from = TimeMath.firstOfMonth(containing: t, offset: offset, calendar: calendar)
            let to = TimeMath.firstOfMonth(containing: t, offset: offset + 1, calendar: calendar)
            return (from, to)
        }
    }

    /// Goal for a period, in seconds. Month is pro-rated: G × daysInMonth / 7.
    static func periodGoal(mode: ReviewMode, from: Date, to: Date, goalMinutes: Double) -> TimeInterval {
        switch mode {
        case .week: return goalMinutes * 60
        case .biweek: return 2 * goalMinutes * 60
        case .month:
            let days = TimeMath.daysBetween(from, to)
            return goalMinutes * 60 * Double(days) / 7
        }
    }

    // MARK: steppers & clamps (mockup: stepPlan / stepGoal / stepAdd / editShift / stepGeoOut)

    /// Stepper path: delegate to the absolute setter so the clamps live once.
    static func stepPlan(_ draft: PlanDraft, field: PlanField, dir: Int) -> PlanDraft {
        switch field {
        case .workMin: return setPlan(draft, field: field, value: draft.workMin + dir * 15)
        case .breakCount: return setPlan(draft, field: field, value: draft.breakCount + dir)
        case .breakMin: return setPlan(draft, field: field, value: draft.breakMin + dir * 15)
        }
    }

    enum PlanField { case workMin, breakCount, breakMin }

    /// Weekly goal stepping: ±0.5h, clamped 5–80h. Input/output in minutes.
    static func stepGoal(_ goalMinutes: Double, dir: Int) -> Double {
        min(80 * 60, max(5 * 60, goalMinutes + Double(dir) * 30))
    }

    /// Stepper path: delegate to the absolute setter so the clamps live once.
    static func stepAddEntry(_ draft: AddEntryDraft, field: AddField, dir: Int) -> AddEntryDraft {
        switch field {
        case .dayOffset: return setAddEntry(draft, field: field, value: draft.dayOffset + dir)
        case .inMin: return setAddEntry(draft, field: field, value: draft.inMin + dir * 15)
        case .outMin: return setAddEntry(draft, field: field, value: draft.outMin + dir * 15)
        case .breakMin: return setAddEntry(draft, field: field, value: draft.breakMin + dir * 15)
        }
    }

    enum AddField { case dayOffset, inMin, outMin, breakMin }

    /// Absolute-set variant of stepAddEntry for the wheel pickers — same clamps,
    /// same cross-field break re-clamp. `value` is days for .dayOffset, minutes
    /// otherwise (mirroring stepAddEntry's field-dependent semantics).
    static func setAddEntry(_ draft: AddEntryDraft, field: AddField, value: Int) -> AddEntryDraft {
        var d = draft
        switch field {
        case .dayOffset: d.dayOffset = min(0, max(-60, value))
        case .inMin: d.inMin = min(d.outMin - 30, max(0, value))
        case .outMin: d.outMin = min(24 * 60 - 15, max(d.inMin + 30, value))
        case .breakMin: d.breakMin = max(0, value)
        }
        d.breakMin = min(d.breakMin, max(0, d.outMin - d.inMin - 15))
        return d
    }

    /// Absolute-set variant of stepPlan for the wheel pickers — same clamps,
    /// same breakCount↔breakMin coupling.
    static func setPlan(_ draft: PlanDraft, field: PlanField, value: Int) -> PlanDraft {
        var d = draft
        switch field {
        case .workMin:
            d.workMin = min(14 * 60, max(30, value))
        case .breakCount:
            d.breakCount = min(4, max(0, value))
            if d.breakCount == 0 { d.breakMin = 0 }
            else if d.breakMin == 0 { d.breakMin = 30 }
        case .breakMin:
            d.breakMin = min(4 * 60, max(0, value))
        }
        return d
    }

    /// mockup: saveAddEntry — break inserted as a single centered segment.
    static func manualEntrySegments(dayStart: Date, draft: AddEntryDraft) -> [SegmentSnapshot] {
        let inT = dayStart.addingTimeInterval(Double(draft.inMin) * 60)
        let outT = dayStart.addingTimeInterval(Double(draft.outMin) * 60)
        guard draft.breakMin > 0 else {
            return [SegmentSnapshot(isBreak: false, start: inT, end: outT)]
        }
        let offMin = TimeMath.jsRound(Double(draft.outMin - draft.inMin - draft.breakMin) / 2)
        let bs = inT.addingTimeInterval(Double(offMin) * 60)
        let be = bs.addingTimeInterval(Double(draft.breakMin) * 60)
        return [
            SegmentSnapshot(isBreak: false, start: inT, end: bs),
            SegmentSnapshot(isBreak: true, start: bs, end: be),
            SegmentSnapshot(isBreak: false, start: be, end: outT),
        ]
    }

    /// The single source of the ±5m edit margins — the clamp functions AND the
    /// wheel pickers' UIDatePicker bounds both derive from these two limits.

    /// Latest allowed clock-in: first-segment-end − 5m (mockup editShift 'in').
    static func clockInLimit(firstSegmentEnd: Date?, clockOut: Date) -> Date {
        (firstSegmentEnd ?? clockOut).addingTimeInterval(-5 * 60)
    }

    /// Earliest allowed clock-out / geo finish: last-segment-start + 5m.
    static func clockOutFloor(lastSegmentStart: Date) -> Date {
        lastSegmentStart.addingTimeInterval(5 * 60)
    }

    /// Absolute-set clamp behind both the 15m stepper and the wheel picker.
    static func clampedClockIn(proposed: Date, firstSegmentEnd: Date?, clockOut: Date) -> Date {
        min(proposed, clockInLimit(firstSegmentEnd: firstSegmentEnd, clockOut: clockOut))
    }

    /// Absolute-set clamp behind both the 15m stepper and the wheel picker.
    static func clampedClockOut(proposed: Date, lastSegmentStart: Date) -> Date {
        max(proposed, clockOutFloor(lastSegmentStart: lastSegmentStart))
    }

    /// mockup editShift 'in': new clock-in, clamped to first-segment-end − 5m.
    static func steppedClockIn(current: Date, dir: Int, firstSegmentEnd: Date?, clockOut: Date) -> Date {
        clampedClockIn(proposed: current.addingTimeInterval(Double(dir * editStepMinutes) * 60),
                       firstSegmentEnd: firstSegmentEnd, clockOut: clockOut)
    }

    /// mockup editShift 'out': new clock-out, clamped to last-segment-start + 5m.
    static func steppedClockOut(current: Date, dir: Int, lastSegmentStart: Date) -> Date {
        clampedClockOut(proposed: current.addingTimeInterval(Double(dir * editStepMinutes) * 60),
                        lastSegmentStart: lastSegmentStart)
    }

    /// mockup geoOutSheet: initial backdated finish time.
    static func initialGeoOutTime(leftAt: Date?, lastSegmentStart: Date, now: Date) -> Date {
        max(leftAt ?? now, lastSegmentStart.addingTimeInterval(5 * 60))
    }

    /// Absolute-set clamp shared by the 5m stepper and the wheel picker:
    /// finish time stays within [last-segment-start + 5m, now].
    static func clampedGeoOutTime(proposed: Date, lastSegmentStart: Date, now: Date) -> Date {
        min(now, max(clockOutFloor(lastSegmentStart: lastSegmentStart), proposed))
    }

    /// mockup stepGeoOut: ±5m, clamped between last-segment-start + 5m and now.
    static func steppedGeoOutTime(current: Date, dir: Int, lastSegmentStart: Date, now: Date) -> Date {
        clampedGeoOutTime(proposed: current.addingTimeInterval(Double(dir * geoStepMinutes) * 60),
                          lastSegmentStart: lastSegmentStart, now: now)
    }

    /// mockup confirmGeoOut: the open segment ends at max(chosen, segStart + 1m).
    static func backdatedSegmentEnd(chosen: Date, lastSegmentStart: Date) -> Date {
        max(chosen, lastSegmentStart.addingTimeInterval(60))
    }

    // MARK: goal line (mockup: goalNeedHtml)

    /// Returns (text, met) — "Need 2h 15m more to hit goal" / "Goal met · +1h 5m over"
    static func goalNeed(worked: TimeInterval, goal: TimeInterval) -> (text: String, met: Bool) {
        let diff = goal - worked
        return diff > 0
            ? ("Need **\(Fmt.dur(diff))** more to hit goal", false)
            : ("Goal met · **+\(Fmt.dur(-diff))** over", true)
    }

    // MARK: CSV export (mockup: exportCSV) + backup import

    /// One row per completed shift with clockIn in [from, to), then the live
    /// shift, then a total row. `break_start` (first break's HH:mm, empty when
    /// none) makes the format round-trippable as a backup: import reconstructs
    /// the break at its real time instead of guessing.
    static func csv(history: [SessionSnapshot],
                    live: SessionSnapshot?,
                    from: Date, to: Date,
                    at: Date,
                    calendar: Calendar = .current) -> String {
        var rows: [[String]] = [["date", "clock_in", "clock_out", "break_minutes", "break_start", "paid_hours"]]
        var total: TimeInterval = 0
        func breakStartField(_ s: SessionSnapshot) -> String {
            s.segments.first(where: \.isBreak).map { Fmt.time24($0.start, calendar: calendar) } ?? ""
        }
        for s in history.sorted(by: { $0.clockIn < $1.clockIn }) where !s.isLive {
            guard s.clockIn >= from && s.clockIn < to, let out = s.clockOut else { continue }
            let w = paidDuration(s, at: at)
            total += w
            rows.append([
                TimeMath.dayKey(s.clockIn, calendar: calendar),
                Fmt.time24(s.clockIn, calendar: calendar),
                Fmt.time24(out, calendar: calendar),
                String(TimeMath.jsRound(breakDuration(s, at: at) / 60)),
                breakStartField(s),
                String(format: "%.2f", w / TimeMath.hour),
            ])
        }
        if let live, live.clockIn >= from && live.clockIn < to {
            let w = paidDuration(live, at: at)
            total += w
            rows.append([
                TimeMath.dayKey(live.clockIn, calendar: calendar),
                Fmt.time24(live.clockIn, calendar: calendar),
                "(active)",
                String(TimeMath.jsRound(breakDuration(live, at: at) / 60)),
                breakStartField(live),
                String(format: "%.2f", w / TimeMath.hour),
            ])
        }
        rows.append(["total", "", "", "", "", String(format: "%.2f", total / TimeMath.hour)])
        return rows.map { $0.joined(separator: ",") }.joined(separator: "\n")
    }

    // MARK: - CSV backup import

    struct ImportedShift: Equatable {
        var clockIn: Date
        var clockOut: Date
        var segments: [SegmentSnapshot]
    }

    struct CSVImportResult: Equatable {
        var shifts: [ImportedShift] = []
        var skippedRows = 0          // malformed lines ("(active)"/total rows don't count)
    }

    /// Parse a backup CSV (this app's export format; tolerant of the legacy
    /// `net_hours` header and a missing `break_start` column). Rules:
    /// - requires date / clock_in / clock_out columns, matched by header name
    /// - "total" and "(active)" rows are ignored
    /// - clock_out ≤ clock_in means the shift crossed midnight (next day)
    /// - break_minutes > 0 becomes one break segment at break_start when that
    ///   fits inside the shift, else centered (Add-Entry rule); the break is
    ///   clamped so at least a minute of work remains on each side
    /// - malformed rows are counted and skipped, never abort the import
    static func parseCSVBackup(_ text: String, calendar: Calendar = .current) -> CSVImportResult {
        var result = CSVImportResult()
        let lines = text.split(whereSeparator: \.isNewline).map(String.init)
        guard let headerLine = lines.first else { return result }
        let header = headerLine.split(separator: ",", omittingEmptySubsequences: false)
            .map { $0.trimmingCharacters(in: .whitespaces).lowercased() }
        guard let dateCol = header.firstIndex(of: "date"),
              let inCol = header.firstIndex(of: "clock_in"),
              let outCol = header.firstIndex(of: "clock_out") else {
            result.skippedRows = max(0, lines.count - 1)
            return result
        }
        let breakCol = header.firstIndex(of: "break_minutes")
        let breakStartCol = header.firstIndex(of: "break_start")

        func minutes(_ field: String) -> Int? {
            let parts = field.split(separator: ":")
            guard parts.count == 2, let h = Int(parts[0]), let m = Int(parts[1]),
                  (0...23).contains(h), (0...59).contains(m) else { return nil }
            return h * 60 + m
        }

        for line in lines.dropFirst() {
            let fields = line.split(separator: ",", omittingEmptySubsequences: false)
                .map { $0.trimmingCharacters(in: .whitespaces) }
            guard fields.count > max(dateCol, inCol, outCol) else {
                if !line.trimmingCharacters(in: .whitespaces).isEmpty { result.skippedRows += 1 }
                continue
            }
            if fields[dateCol] == "total" { continue }
            if fields[outCol] == "(active)" { continue }

            let dateParts = fields[dateCol].split(separator: "-").compactMap { Int($0) }
            guard dateParts.count == 3,
                  let inMin = minutes(fields[inCol]),
                  let outMinRaw = minutes(fields[outCol]) else {
                result.skippedRows += 1
                continue
            }
            var comps = DateComponents()
            comps.year = dateParts[0]; comps.month = dateParts[1]; comps.day = dateParts[2]
            guard let dayStart = calendar.date(from: comps) else {
                result.skippedRows += 1
                continue
            }
            func timeOn(_ minutesIntoDay: Int, dayOffset: Int = 0) -> Date? {
                let day = TimeMath.addDays(dayStart, dayOffset, calendar: calendar)
                return calendar.date(bySettingHour: minutesIntoDay / 60,
                                     minute: minutesIntoDay % 60, second: 0, of: day)
            }
            let crossesMidnight = outMinRaw <= inMin
            guard let clockIn = timeOn(inMin),
                  let clockOut = timeOn(outMinRaw, dayOffset: crossesMidnight ? 1 : 0),
                  clockOut > clockIn else {
                result.skippedRows += 1
                continue
            }

            let spanMin = Int(clockOut.timeIntervalSince(clockIn) / 60)
            var breakMin = breakCol.flatMap { $0 < fields.count ? Int(fields[$0]) : nil } ?? 0
            breakMin = max(0, min(breakMin, spanMin - 2))   // ≥1m work on each side

            var segments: [SegmentSnapshot]
            if breakMin <= 0 {
                segments = [SegmentSnapshot(isBreak: false, start: clockIn, end: clockOut)]
            } else {
                // Prefer the recorded break start when it fits; else center it.
                var bsMin: Int? = breakStartCol
                    .flatMap { $0 < fields.count ? minutes(fields[$0]) : nil }
                    .map { $0 <= inMin && crossesMidnight ? $0 + 24 * 60 : $0 }
                    .map { $0 - inMin }                     // offset from clock-in
                if let off = bsMin, !(off >= 1 && off + breakMin <= spanMin - 1) { bsMin = nil }
                let offset = bsMin ?? TimeMath.jsRound(Double(spanMin - breakMin) / 2)
                let bs = clockIn.addingTimeInterval(Double(offset) * 60)
                let be = bs.addingTimeInterval(Double(breakMin) * 60)
                segments = [
                    SegmentSnapshot(isBreak: false, start: clockIn, end: bs),
                    SegmentSnapshot(isBreak: true, start: bs, end: be),
                    SegmentSnapshot(isBreak: false, start: be, end: clockOut),
                ]
            }
            result.shifts.append(ImportedShift(clockIn: clockIn, clockOut: clockOut, segments: segments))
        }
        return result
    }
}
