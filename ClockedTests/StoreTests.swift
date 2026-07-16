import XCTest
import SwiftData
@testable import Clocked

// TrackerStore mutations against an in-memory SwiftData container.
// Invariants under test: exactly one open segment while a shift is active,
// a break never ends the shift, clamps apply through the store.
// A fresh store per test — never TrackerStore.shared.
@MainActor
final class StoreTests: XCTestCase {

    private func openSegmentCount(_ shift: Shift) -> Int {
        shift.orderedSegments.filter { $0.end == nil }.count
    }

    func testClockInCreatesOpenWorkSegmentAndRecordsPlan() {
        let store = TrackerStore(inMemory: true)
        store.clockIn(at: date(2026, 7, 15, 9, 0),
                      plan: PlanDraft(workMin: 405, breakCount: 2, breakMin: 45))
        guard let shift = store.liveShift else { return XCTFail("no live shift after clockIn") }
        XCTAssertNil(shift.clockOut)
        XCTAssertEqual(shift.clockIn, date(2026, 7, 15, 9, 0))
        XCTAssertEqual(shift.orderedSegments.count, 1)
        let seg = shift.orderedSegments[0]
        XCTAssertFalse(seg.isBreak)
        XCTAssertEqual(seg.start, date(2026, 7, 15, 9, 0))
        XCTAssertNil(seg.end)
        XCTAssertEqual(shift.plannedWorkMinutes, 405)
        XCTAssertEqual(shift.plannedBreakCount, 2)
        XCTAssertEqual(shift.plannedBreakMinutes, 45)
        XCTAssertEqual(store.trackState, .working)
    }

    func testStartBreakKeepsShiftOpenWithOneOpenSegment() {
        let store = TrackerStore(inMemory: true)
        store.clockIn(at: date(2026, 7, 15, 9, 0))
        store.startBreak(at: date(2026, 7, 15, 12, 0))
        guard let shift = store.liveShift else { return XCTFail("break must not end the shift") }
        XCTAssertNil(shift.clockOut)
        let segs = shift.orderedSegments
        XCTAssertEqual(segs.count, 2)
        XCTAssertEqual(segs[0].end, date(2026, 7, 15, 12, 0))   // work segment closed
        XCTAssertTrue(segs[1].isBreak)
        XCTAssertEqual(segs[1].start, date(2026, 7, 15, 12, 0))
        XCTAssertNil(segs[1].end)
        XCTAssertEqual(openSegmentCount(shift), 1)
        XCTAssertEqual(store.trackState, .onBreak)
    }

    func testResumeWorkFlipsBackToWorking() {
        let store = TrackerStore(inMemory: true)
        store.clockIn(at: date(2026, 7, 15, 9, 0))
        store.startBreak(at: date(2026, 7, 15, 12, 0))
        store.resumeWork(at: date(2026, 7, 15, 12, 30))
        guard let shift = store.liveShift else { return XCTFail("still live after resume") }
        let segs = shift.orderedSegments
        XCTAssertEqual(segs.count, 3)
        XCTAssertEqual(segs[1].end, date(2026, 7, 15, 12, 30))  // break closed
        XCTAssertFalse(segs[2].isBreak)
        XCTAssertNil(segs[2].end)
        XCTAssertEqual(openSegmentCount(shift), 1)
        XCTAssertEqual(store.trackState, .working)
    }

    func testClockOutFinalizesShift() {
        let store = TrackerStore(inMemory: true)
        store.clockIn(at: date(2026, 7, 15, 9, 0))
        store.startBreak(at: date(2026, 7, 15, 12, 0))
        store.resumeWork(at: date(2026, 7, 15, 12, 30))
        store.clockOut(at: date(2026, 7, 15, 16, 30))
        XCTAssertNil(store.liveShift)
        XCTAssertEqual(store.completedShifts.count, 1)
        let shift = store.completedShifts[0]
        XCTAssertEqual(shift.clockOut, date(2026, 7, 15, 16, 30))
        XCTAssertEqual(openSegmentCount(shift), 0)
        let snap = shift.snapshot
        // net = 9–12 work + 12:30–16:30 work = 7h; break 30m
        XCTAssertEqual(Engine.workDuration(snap, at: date(2026, 7, 15, 16, 30)), 7 * 3600)
        XCTAssertEqual(Engine.breakDuration(snap, at: date(2026, 7, 15, 16, 30)), 1800)
        XCTAssertEqual(store.trackState, .out)
    }

    // Geofence flow: net hours exclude everything after the chosen finish.
    func testBackdatedClockOutExcludesTimeAfterFinish() {
        let store = TrackerStore(inMemory: true)
        store.clockIn(at: date(2026, 7, 15, 9, 0))
        // "Now" is much later, but she was done at 11:00.
        store.backdatedClockOut(finishedAt: date(2026, 7, 15, 11, 0))
        XCTAssertNil(store.liveShift)
        let shift = store.completedShifts[0]
        XCTAssertEqual(shift.clockOut, date(2026, 7, 15, 11, 0))
        XCTAssertEqual(shift.orderedSegments.last?.end, date(2026, 7, 15, 11, 0))
        // Evaluated well after the finish, net stays 2h.
        XCTAssertEqual(Engine.workDuration(shift.snapshot, at: date(2026, 7, 15, 13, 0)), 2 * 3600)

        // Chosen ≤ segment start + 60s → clamped to start + 1m (mockup: max(chosen, last.s + MIN)).
        let store2 = TrackerStore(inMemory: true)
        store2.clockIn(at: date(2026, 7, 15, 9, 0))
        store2.backdatedClockOut(finishedAt: date(2026, 7, 15, 8, 0))
        XCTAssertEqual(store2.completedShifts[0].clockOut, date(2026, 7, 15, 9, 1))
    }

    func testAddManualEntryInsertsCenteredBreak() {
        let store = TrackerStore(inMemory: true)
        store.addManualEntry(AddEntryDraft(dayOffset: -1, inMin: 660, outMin: 1080, breakMin: 60),
                             today: anchorNoon, calendar: testCal)
        XCTAssertEqual(store.completedShifts.count, 1)
        let shift = store.completedShifts[0]
        XCTAssertEqual(shift.clockIn, date(2026, 7, 14, 11, 0))     // yesterday relative to anchor
        XCTAssertEqual(shift.clockOut, date(2026, 7, 14, 18, 0))
        let segs = shift.orderedSegments
        XCTAssertEqual(segs.count, 3)
        XCTAssertTrue(segs[1].isBreak)
        XCTAssertEqual(segs[1].start, date(2026, 7, 14, 14, 0))     // centered
        XCTAssertEqual(segs[1].end, date(2026, 7, 14, 15, 0))
        XCTAssertEqual(Engine.workDuration(shift.snapshot, at: date(2026, 7, 14, 18, 0)), 6 * 3600)
    }

    // 15m steps through the store; first segment start follows clockIn.
    func testAdjustClockInFollowsAndClamps() {
        let store = TrackerStore(inMemory: true)
        // Today 11:00–11:30, no break → clamp limit = 11:30 − 5m = 11:25.
        store.addManualEntry(AddEntryDraft(dayOffset: 0, inMin: 660, outMin: 690, breakMin: 0),
                             today: anchorNoon, calendar: testCal)
        let shift = store.completedShifts[0]
        store.adjustClockIn(shift, direction: 1)
        XCTAssertEqual(shift.clockIn, date(2026, 7, 15, 11, 15))
        XCTAssertEqual(shift.orderedSegments.first?.start, date(2026, 7, 15, 11, 15))
        store.adjustClockIn(shift, direction: 1)                    // would be 11:30 → clamped
        XCTAssertEqual(shift.clockIn, date(2026, 7, 15, 11, 25))
        XCTAssertEqual(shift.orderedSegments.first?.start, date(2026, 7, 15, 11, 25))
        store.adjustClockIn(shift, direction: -1)                   // earlier is unbounded
        XCTAssertEqual(shift.clockIn, date(2026, 7, 15, 11, 10))
    }

    // Last segment end follows clockOut; clamp ≥ lastSegmentStart + 5m.
    func testAdjustClockOutFollowsAndClamps() {
        let store = TrackerStore(inMemory: true)
        store.addManualEntry(AddEntryDraft(dayOffset: 0, inMin: 660, outMin: 690, breakMin: 0),
                             today: anchorNoon, calendar: testCal)
        let shift = store.completedShifts[0]
        store.adjustClockOut(shift, direction: -1)
        XCTAssertEqual(shift.clockOut, date(2026, 7, 15, 11, 15))
        XCTAssertEqual(shift.orderedSegments.last?.end, date(2026, 7, 15, 11, 15))
        store.adjustClockOut(shift, direction: -1)                  // would be 11:00 → clamp 11:05
        XCTAssertEqual(shift.clockOut, date(2026, 7, 15, 11, 5))
        XCTAssertEqual(shift.orderedSegments.last?.end, date(2026, 7, 15, 11, 5))
        store.adjustClockOut(shift, direction: -1)                  // stays at the clamp
        XCTAssertEqual(shift.clockOut, date(2026, 7, 15, 11, 5))
        store.adjustClockOut(shift, direction: 1)                   // later is unbounded
        XCTAssertEqual(shift.clockOut, date(2026, 7, 15, 11, 20))
        XCTAssertEqual(shift.orderedSegments.last?.end, date(2026, 7, 15, 11, 20))
    }

    func testDeleteShiftRemovesIt() {
        let store = TrackerStore(inMemory: true)
        store.addManualEntry(AddEntryDraft(dayOffset: 0, inMin: 660, outMin: 1080, breakMin: 0),
                             today: anchorNoon, calendar: testCal)
        XCTAssertEqual(store.completedShifts.count, 1)
        store.deleteShift(store.completedShifts[0])
        XCTAssertTrue(store.completedShifts.isEmpty)
        XCTAssertNil(store.liveShift)
    }
}
