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
                .appendingPathComponent("Hours.sqlite") {
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

    func adjustClockIn(_ shift: Shift, direction: Int) {
        guard shift.clockOut != nil else { return }
        let ordered = shift.orderedSegments
        guard let first = ordered.first else { return }
        let newIn = Engine.steppedClockIn(
            current: shift.clockIn, dir: direction,
            firstSegmentEnd: first.end, clockOut: shift.clockOut!
        )
        shift.clockIn = newIn
        first.start = newIn
        persistAndNotify()
    }

    func adjustClockOut(_ shift: Shift, direction: Int) {
        guard let out = shift.clockOut,
              let last = shift.orderedSegments.last else { return }
        let newOut = Engine.steppedClockOut(current: out, dir: direction, lastSegmentStart: last.start)
        shift.clockOut = newOut
        last.end = newOut
        persistAndNotify()
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
