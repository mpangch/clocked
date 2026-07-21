import Foundation
import SwiftData
import WidgetKit

extension Notification.Name {
    /// Posted after every tracking mutation (clock events, edits, deletes, adds).
    static let trackingDidChange = Notification.Name("trackingDidChange")
}

/// Shared data controller: owns the App Group SwiftData store and every mutation.
/// The app UI, App Intents (widget/Live Activity buttons), and geofence flow all
/// route through here so the invariants hold everywhere:
///   - exactly one open segment while a shift is active
///   - a break never ends the shift
///   - any clock event clears the geofence away state
@MainActor
final class TrackerStore {
    static let shared = TrackerStore()

    let container: ModelContainer
    var context: ModelContext { container.mainContext }

    init(inMemory: Bool = false) {
        let schema = Schema([Shift.self, Segment.self])
        do {
            if inMemory {
                let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
                container = try ModelContainer(for: schema, configurations: [config])
            } else if let groupURL = FileManager.default
                .containerURL(forSecurityApplicationGroupIdentifier: AppGroup.id)?
                .appendingPathComponent("Clocked.sqlite") {
                let config = ModelConfiguration(schema: schema, url: groupURL)
                container = try ModelContainer(for: schema, configurations: [config])
            } else {
                container = try ModelContainer(for: schema)
            }
        } catch {
            fatalError("Failed to create SwiftData container: \(error)")
        }
    }

    // MARK: - Queries

    /// The active shift (clockOut == nil), if any.
    var liveShift: Shift? {
        var fd = FetchDescriptor<Shift>(
            predicate: #Predicate { $0.clockOut == nil },
            sortBy: [SortDescriptor(\.clockIn, order: .reverse)]
        )
        fd.fetchLimit = 1
        return (try? context.fetch(fd))?.first
    }

    /// Completed shifts, oldest first (mockup keeps `history` sorted by clock-in).
    var completedShifts: [Shift] {
        let fd = FetchDescriptor<Shift>(
            predicate: #Predicate { $0.clockOut != nil },
            sortBy: [SortDescriptor(\.clockIn)]
        )
        return (try? context.fetch(fd)) ?? []
    }

    var historySnapshots: [SessionSnapshot] { completedShifts.map(\.snapshot) }
    var liveSnapshot: SessionSnapshot? { liveShift?.snapshot }

    /// History + live, i.e. the union the mockup's sessionsOn() sees.
    var allSnapshots: [SessionSnapshot] {
        var out = historySnapshots
        if let live = liveSnapshot { out.append(live) }
        return out
    }

    // MARK: - Date-bounded fetches
    // A shift belongs to the calendar day of its clockIn, so every aggregate
    // (day, week, review period, 8-week stats window) only ever needs shifts
    // whose clockIn falls in a known range. Bounding the fetch keeps per-render
    // cost proportional to the window, not to lifetime history — the views
    // re-render every 1–30 s, and the store grows forever.

    /// Completed shifts with clockIn in [from, to), oldest first.
    func completedShifts(from: Date, to: Date) -> [Shift] {
        let fd = FetchDescriptor<Shift>(
            predicate: #Predicate { $0.clockOut != nil && $0.clockIn >= from && $0.clockIn < to },
            sortBy: [SortDescriptor(\.clockIn)]
        )
        return (try? context.fetch(fd)) ?? []
    }

    /// Completed-shift snapshots with clockIn in [from, to).
    func historySnapshots(from: Date, to: Date) -> [SessionSnapshot] {
        completedShifts(from: from, to: to).map(\.snapshot)
    }

    /// History + live for [from, to) — the live shift is included only when
    /// its clockIn is in range (day/period attribution follows clockIn).
    func allSnapshots(from: Date, to: Date) -> [SessionSnapshot] {
        var out = historySnapshots(from: from, to: to)
        if let live = liveSnapshot, live.clockIn >= from, live.clockIn < to {
            out.append(live)
        }
        return out
    }

    var trackState: TrackState { Engine.state(live: liveSnapshot) }

    // MARK: - Clock actions (mockup: clockIn / startBreak / resumeWork / confirmClockOut)

    func clockIn(at date: Date = .now, plan: PlanDraft? = nil) {
        guard liveShift == nil else { return }
        let shift = Shift(
            clockIn: date,
            plannedWorkMinutes: plan?.workMin,
            plannedBreakCount: plan?.breakCount,
            plannedBreakMinutes: plan?.breakMin
        )
        context.insert(shift)
        shift.segments.append(Segment(isBreak: false, start: date))
        AppSettings.shared.clearAwayState()
        persistAndNotify()
    }

    func startBreak(at date: Date = .now) {
        guard let shift = liveShift, trackState == .working,
              let open = openSegment(of: shift) else { return }
        open.end = date
        shift.segments.append(Segment(isBreak: true, start: date))
        persistAndNotify()
    }

    func resumeWork(at date: Date = .now) {
        guard let shift = liveShift, trackState == .onBreak,
              let open = openSegment(of: shift) else { return }
        open.end = date
        shift.segments.append(Segment(isBreak: false, start: date))
        persistAndNotify()
    }

    func clockOut(at date: Date = .now) {
        guard let shift = liveShift else { return }
        if let open = openSegment(of: shift) { open.end = date }
        shift.clockOut = date
        AppSettings.shared.clearAwayState()
        persistAndNotify()
    }

    /// mockup: confirmGeoOut — backdate the clock-out to a chosen finish time.
    func backdatedClockOut(finishedAt chosen: Date) {
        guard let shift = liveShift,
              let last = shift.orderedSegments.last else { return }
        let end = Engine.backdatedSegmentEnd(chosen: chosen, lastSegmentStart: last.start)
        last.end = end
        shift.clockOut = end
        AppSettings.shared.clearAwayState()
        persistAndNotify()
    }

    // MARK: - Editing (mockup: editShift / deleteShift / saveAddEntry)

    /// 15m stepper path — delegates to the absolute setter so the clamp lives once.
    func adjustClockIn(_ shift: Shift, direction: Int) {
        setClockIn(shift, to: shift.clockIn.addingTimeInterval(Double(direction * Engine.editStepMinutes) * 60))
    }

    /// 15m stepper path — delegates to the absolute setter so the clamp lives once.
    func adjustClockOut(_ shift: Shift, direction: Int) {
        guard let out = shift.clockOut else { return }
        setClockOut(shift, to: out.addingTimeInterval(Double(direction * Engine.editStepMinutes) * 60))
    }

    /// Set the clock-in to an absolute time (wheel picker), clamped like the
    /// stepper. Works for the LIVE shift too — the forgot-to-clock-in fix:
    /// with no clock-out yet, "now" bounds the clamp, so the clock-in can be
    /// backdated freely but never pushed later than now − 5m.
    func setClockIn(_ shift: Shift, to proposed: Date, now: Date = .now) {
        guard isEditable(shift) else { return }
        let ordered = shift.orderedSegments
        guard let first = ordered.first else { return }
        let newIn = Engine.clampedClockIn(proposed: proposed,
                                          firstSegmentEnd: first.end,
                                          clockOut: shift.clockOut ?? now)
        shift.clockIn = newIn
        first.start = newIn
        persistAndNotify()
    }

    /// Set the clock-out to an absolute time (wheel picker), clamped like the stepper.
    func setClockOut(_ shift: Shift, to proposed: Date) {
        guard isEditable(shift), shift.clockOut != nil,
              let last = shift.orderedSegments.last else { return }
        let newOut = Engine.clampedClockOut(proposed: proposed, lastSegmentStart: last.start)
        shift.clockOut = newOut
        last.end = newOut
        persistAndNotify()
    }

    /// A decelerating wheel can fire its final valueChanged after "Delete
    /// session" already removed the shift — mutating a deleted @Model faults.
    private func isEditable(_ shift: Shift) -> Bool {
        !shift.isDeleted && shift.modelContext != nil
    }

    // MARK: - CSV backup import

    /// Insert parsed backup shifts, skipping any whose clock-in minute already
    /// exists (re-importing the same backup is a no-op, and restoring onto a
    /// device that already has some data never duplicates it).
    @discardableResult
    func importShifts(_ imported: [Engine.ImportedShift]) -> (inserted: Int, duplicates: Int) {
        guard !imported.isEmpty else { return (0, 0) }
        let minDate = imported.map(\.clockIn).min()!.addingTimeInterval(-120)
        let maxDate = imported.map(\.clockOut).max()!.addingTimeInterval(120)
        // CSV times are minute-precision; recorded shifts carry seconds — key
        // both by the floored minute so a round-trip matches its own source.
        var existing = Set(completedShifts(from: minDate, to: maxDate)
            .map { Int($0.clockIn.timeIntervalSince1970 / 60) })
        if let live = liveShift { existing.insert(Int(live.clockIn.timeIntervalSince1970 / 60)) }

        var inserted = 0, duplicates = 0
        for s in imported {
            let key = Int(s.clockIn.timeIntervalSince1970 / 60)
            if existing.contains(key) { duplicates += 1; continue }
            existing.insert(key)
            let shift = Shift(clockIn: s.clockIn, clockOut: s.clockOut)
            context.insert(shift)
            for seg in s.segments {
                shift.segments.append(Segment(isBreak: seg.isBreak, start: seg.start, end: seg.end))
            }
            inserted += 1
        }
        persistAndNotify()
        return (inserted, duplicates)
    }

    func deleteShift(_ shift: Shift) {
        context.delete(shift)
        persistAndNotify()
    }

    func addManualEntry(_ draft: AddEntryDraft, today: Date = .now, calendar: Calendar = .current) {
        let dayStart = TimeMath.addDays(TimeMath.startOfDay(today, calendar: calendar),
                                        draft.dayOffset, calendar: calendar)
        let segs = Engine.manualEntrySegments(dayStart: dayStart, draft: draft)
        guard let first = segs.first, let last = segs.last, let out = last.end else { return }
        let shift = Shift(clockIn: first.start, clockOut: out)
        context.insert(shift)
        for s in segs {
            shift.segments.append(Segment(isBreak: s.isBreak, start: s.start, end: s.end))
        }
        persistAndNotify()
    }

    // MARK: - Helpers

    private func openSegment(of shift: Shift) -> Segment? {
        shift.orderedSegments.last(where: { $0.end == nil })
    }

    private func persistAndNotify() {
        try? context.save()
        WidgetCenter.shared.reloadAllTimelines()
        LiveActivityManager.shared.sync(with: self)
        NotificationCenter.default.post(name: .trackingDidChange, object: nil)
    }
}
