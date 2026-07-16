import SwiftUI
import SwiftData

// MARK: - Day detail sheet (mockup: openDay / editShift / deleteShift)

struct DayDetailSheet: View {
    var day: Date

    @Environment(\.dismiss) private var dismiss
    @Environment(AppModel.self) private var model
    /// Present so SwiftData changes (stepper edits, deletes) re-render this sheet.
    @Query(sort: \Shift.clockIn) private var shifts: [Shift]

    /// Wheel expansion keyed by shift IDENTITY (not list position): deletes and
    /// clock-in re-sorts renumber sessions, and a positional key would hand the
    /// open wheel to a different shift mid-gesture.
    struct WheelTag: Hashable {
        let id: PersistentIdentifier
        let isClockOut: Bool
    }
    @State private var expandedWheel: WheelTag?
    @State private var rekeyTask: Task<Void, Never>?

    /// mockup editShift ends with openDay(dkey(s.in)): when a clock-in edit
    /// crosses midnight, the sheet follows the session to its new day instead
    /// of letting it silently vanish from the current one.
    private func adjustClockIn(_ shift: Shift, direction: Int) {
        TrackerStore.shared.adjustClockIn(shift, direction: direction)
        followSessionIfDayChanged(shift)
    }

    private func setClockIn(_ shift: Shift, to date: Date) {
        TrackerStore.shared.setClockIn(shift, to: date)
        followSessionIfDayChanged(shift)
    }

    /// Debounced: the date+time wheel makes crossing midnight a one-flick
    /// action, and a still-decelerating second wheel component must not re-key
    /// the sheet a second time mid-transition.
    private func followSessionIfDayChanged(_ shift: Shift) {
        guard TimeMath.dayKey(shift.clockIn) != TimeMath.dayKey(day) else { return }
        rekeyTask?.cancel()
        rekeyTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(0.8))
            guard !Task.isCancelled, !shift.isDeleted,
                  TimeMath.dayKey(shift.clockIn) != TimeMath.dayKey(day) else { return }
            model.activeSheet = .dayDetail(TimeMath.startOfDay(shift.clockIn))
        }
    }

    var body: some View {
        TimelineView(.periodic(from: .now, by: 30)) { timeline in
            content(now: timeline.date)
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
    }

    /// The actual Shift models for this day (completed + live), sorted by clock-in,
    /// so stepper edits map 1:1 to models.
    private var dayShifts: [Shift] {
        let key = TimeMath.dayKey(day)
        var out = TrackerStore.shared.completedShifts.filter { TimeMath.dayKey($0.clockIn) == key }
        if let live = TrackerStore.shared.liveShift, TimeMath.dayKey(live.clockIn) == key {
            out.append(live)
        }
        return out.sorted { $0.clockIn < $1.clockIn }
    }

    @ViewBuilder
    private func content(now: Date) -> some View {
        let sessions = dayShifts
        let snapshots = sessions.map(\.snapshot)
        let totals = Engine.dayTotals(on: day, sessions: snapshots, at: now)
        let hasLive = sessions.contains { $0.clockOut == nil }

        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Text(Fmt.weekdayDate(day))
                    .font(.system(size: 20, weight: .heavy))
                    .foregroundStyle(Theme.label)
                if let first = totals.first, let last = totals.last {
                    Text(Fmt.time(first) + " – " + (hasLive ? "now" : Fmt.time(last)))
                        .font(.system(size: 14))
                        .foregroundStyle(Theme.secondary)
                        .padding(.top, 4)
                }

                if !sessions.isEmpty {
                    timelineBar(snapshots: snapshots, totals: totals, now: now)
                        .padding(.top, 12)
                        .padding(.bottom, 6)
                    if let first = totals.first, let last = totals.last {
                        HStack {
                            Text(Fmt.time(first))
                            Spacer()
                            Text(hasLive ? "now" : Fmt.time(last))
                        }
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Theme.tertiary)
                        .padding(.bottom, 10)
                    }

                    ForEach(Array(sessions.enumerated()), id: \.element.persistentModelID) { i, shift in
                        sessionBlock(index: i + 1, shift: shift, now: now)
                    }

                    VStack(spacing: 0) {
                        SummaryRow(key: "Worked", value: Fmt.dur(totals.work), valueColor: Theme.greenD)
                        SummaryRow(key: "Breaks", value: Fmt.dur(totals.brk), valueColor: Theme.amberD)
                    }
                    .padding(.top, 10)
                    .overlay(alignment: .top) {
                        Rectangle().fill(Theme.separator).frame(height: 0.5)
                    }
                }

                BigButton(title: "Done", background: Theme.inset, foreground: Theme.label) {
                    dismiss()
                }
                .padding(.top, 12)
            }
            .padding(20)
        }
        .background(Theme.card)
    }

    // MARK: proportional timeline (mockup: .timeline)

    private struct TimelineItem: Identifiable {
        let id: Int
        let color: Color?    // nil = transparent gap
        let fraction: Double
    }

    private func timelineBar(snapshots: [SessionSnapshot], totals: DayTotals, now: Date) -> some View {
        let items = timelineItems(snapshots: snapshots, totals: totals, now: now)
        return GeometryReader { geo in
            HStack(spacing: 0) {
                ForEach(items) { item in
                    Rectangle()
                        .fill(item.color ?? Color.clear)
                        .frame(width: max(0, item.fraction) * geo.size.width)
                }
            }
        }
        .frame(height: 26)
        .background(Theme.inset)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private func timelineItems(snapshots: [SessionSnapshot], totals: DayTotals, now: Date) -> [TimelineItem] {
        guard let first = totals.first, let last = totals.last else { return [] }
        let span = max(1, last.timeIntervalSince(first))
        var items: [TimelineItem] = []
        var prevEnd: Date?
        var i = 0
        for s in snapshots {
            for seg in s.segments {
                if let p = prevEnd, seg.start > p {
                    items.append(TimelineItem(id: i, color: nil,
                                              fraction: seg.start.timeIntervalSince(p) / span))
                    i += 1
                }
                items.append(TimelineItem(id: i,
                                          color: seg.isBreak ? Theme.amber : Theme.green,
                                          fraction: max(0.005, Engine.segDuration(seg, at: now) / span)))
                i += 1
                prevEnd = seg.end ?? now
            }
        }
        return items
    }

    // MARK: per-session block

    @ViewBuilder
    private func sessionBlock(index: Int, shift: Shift, now: Date) -> some View {
        let isLive = shift.clockOut == nil
        // One sort per block: the wheel bounds and the segment list share it.
        let segments = shift.orderedSegments
        return VStack(alignment: .leading, spacing: 0) {
            Text("Session \(index)\(isLive ? " · active now" : "")".uppercased())
                .font(.system(size: 11.5, weight: .bold))
                .kerning(0.5)
                .foregroundStyle(Theme.tertiary)
                .padding(.top, 14)
                .padding(.bottom, 2)

            if !isLive, let out = shift.clockOut {
                ExpandableStepperRow(
                    label: "Clock in",
                    sublabel: "fix in 15m steps",
                    value: Fmt.time(shift.clockIn),
                    onMinus: { adjustClockIn(shift, direction: -1) },
                    onPlus: { adjustClockIn(shift, direction: 1) },
                    tag: WheelTag(id: shift.persistentModelID, isClockOut: false),
                    expanded: $expandedWheel
                ) {
                    // 1-minute precision: real punches are off the 15m grid
                    // (9:07), and a coarser wheel would silently shave minutes
                    // the moment any other column is scrolled.
                    WheelDatePicker(
                        mode: .dateAndTime,
                        minuteInterval: 1,
                        maximumDate: Engine.clockInLimit(firstSegmentEnd: segments.first?.end, clockOut: out),
                        date: Binding(get: { shift.clockIn },
                                      set: { setClockIn(shift, to: $0) })
                    )
                }
                ExpandableStepperRow(
                    label: "Clock out",
                    sublabel: "forgot? adjust it here",
                    value: Fmt.time(out),
                    onMinus: { TrackerStore.shared.adjustClockOut(shift, direction: -1) },
                    onPlus: { TrackerStore.shared.adjustClockOut(shift, direction: 1) },
                    tag: WheelTag(id: shift.persistentModelID, isClockOut: true),
                    expanded: $expandedWheel
                ) {
                    WheelDatePicker(
                        mode: .dateAndTime,
                        minuteInterval: 1,
                        minimumDate: Engine.clockOutFloor(lastSegmentStart: segments.last?.start ?? shift.clockIn),
                        date: Binding(get: { shift.clockOut ?? out },
                                      set: { TrackerStore.shared.setClockOut(shift, to: $0) })
                    )
                }
            }

            ForEach(segments) { seg in
                SummaryRow(
                    key: seg.isBreak ? "Break (unpaid)" : "Work",
                    value: segmentValue(seg, now: now)
                )
            }

            if !isLive {
                HStack {
                    Spacer()
                    Button {
                        deleteSession(shift)
                    } label: {
                        Text("Delete session")
                            .font(.system(size: 12.5, weight: .bold))
                            .foregroundStyle(Theme.redD)
                            .padding(.horizontal, 11)
                            .padding(.vertical, 7)
                            .background(Theme.redT)
                            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }
                .padding(.top, 8)
            }
        }
    }

    private func segmentValue(_ seg: Segment, now: Date) -> String {
        let snap = SegmentSnapshot(isBreak: seg.isBreak, start: seg.start, end: seg.end)
        let end = seg.end.map { Fmt.time($0) } ?? "now"
        return Fmt.time(seg.start) + " – " + end + " · " + Fmt.dur(Engine.segDuration(snap, at: now))
    }

    private func deleteSession(_ shift: Shift) {
        let remaining = dayShifts.count - 1
        TrackerStore.shared.deleteShift(shift)
        if remaining <= 0 { dismiss() }
    }
}
