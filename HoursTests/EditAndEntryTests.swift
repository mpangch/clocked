import XCTest
@testable import Hours

// Edit clamps (mockup: editShift), manual add entry (stepAdd/saveAddEntry),
// plan/goal steppers (stepPlan/stepGoal), and the geofence backdated
// clock-out clamps (geoOutSheet/stepGeoOut/confirmGeoOut).
final class EditAndEntryTests: XCTestCase {

    // MARK: editShift 'in' — clamp to firstSegmentEnd − 5m, unbounded earlier.

    func testSteppedClockInClampAndUnbounded() {
        // 10m before the limit: +15 lands exactly on the limit (11:55).
        XCTAssertEqual(Engine.steppedClockIn(current: date(2026, 7, 14, 11, 45), dir: 1,
                                             firstSegmentEnd: date(2026, 7, 14, 12, 0),
                                             clockOut: date(2026, 7, 14, 16, 0)),
                       date(2026, 7, 14, 11, 55))
        // Moving earlier is unbounded.
        XCTAssertEqual(Engine.steppedClockIn(current: date(2026, 7, 14, 9, 0), dir: -1,
                                             firstSegmentEnd: date(2026, 7, 14, 12, 0),
                                             clockOut: date(2026, 7, 14, 16, 0)),
                       date(2026, 7, 14, 8, 45))
        // firstSegmentEnd nil → falls back to clockOut (JS: s.segs[0].e ?? s.out).
        XCTAssertEqual(Engine.steppedClockIn(current: date(2026, 7, 14, 9, 40), dir: 1,
                                             firstSegmentEnd: nil,
                                             clockOut: date(2026, 7, 14, 10, 0)),
                       date(2026, 7, 14, 9, 55))
    }

    // MARK: editShift 'out' — clamp to lastSegmentStart + 5m, unbounded later.

    func testSteppedClockOutClampAndUnbounded() {
        XCTAssertEqual(Engine.steppedClockOut(current: date(2026, 7, 14, 16, 10), dir: -1,
                                              lastSegmentStart: date(2026, 7, 14, 16, 0)),
                       date(2026, 7, 14, 16, 5))
        XCTAssertEqual(Engine.steppedClockOut(current: date(2026, 7, 14, 16, 10), dir: 1,
                                              lastSegmentStart: date(2026, 7, 14, 16, 0)),
                       date(2026, 7, 14, 16, 25))
    }

    // MARK: stepAdd clamps

    func testStepAddEntryClamps() {
        // dayOffset ∈ [−60, 0]
        XCTAssertEqual(Engine.stepAddEntry(AddEntryDraft(dayOffset: 0, inMin: 600, outMin: 900, breakMin: 0),
                                           field: .dayOffset, dir: 1).dayOffset, 0)
        XCTAssertEqual(Engine.stepAddEntry(AddEntryDraft(dayOffset: -60, inMin: 600, outMin: 900, breakMin: 0),
                                           field: .dayOffset, dir: -1).dayOffset, -60)
        XCTAssertEqual(Engine.stepAddEntry(AddEntryDraft(dayOffset: -1, inMin: 600, outMin: 900, breakMin: 0),
                                           field: .dayOffset, dir: 1).dayOffset, 0)
        // inMin ≥ 0 and ≤ outMin − 30
        XCTAssertEqual(Engine.stepAddEntry(AddEntryDraft(dayOffset: 0, inMin: 1050, outMin: 1080, breakMin: 0),
                                           field: .inMin, dir: 1).inMin, 1050)
        XCTAssertEqual(Engine.stepAddEntry(AddEntryDraft(dayOffset: 0, inMin: 0, outMin: 300, breakMin: 0),
                                           field: .inMin, dir: -1).inMin, 0)
        XCTAssertEqual(Engine.stepAddEntry(AddEntryDraft(dayOffset: 0, inMin: 600, outMin: 900, breakMin: 0),
                                           field: .inMin, dir: 1).inMin, 615)
        // outMin ≤ 23:45 (1425) and ≥ inMin + 30
        XCTAssertEqual(Engine.stepAddEntry(AddEntryDraft(dayOffset: 0, inMin: 600, outMin: 1425, breakMin: 0),
                                           field: .outMin, dir: 1).outMin, 1425)
        XCTAssertEqual(Engine.stepAddEntry(AddEntryDraft(dayOffset: 0, inMin: 660, outMin: 690, breakMin: 0),
                                           field: .outMin, dir: -1).outMin, 690)
    }

    // JS re-clamps breakMin after EVERY stepAdd: ≤ max(0, out − in − 15).
    func testStepAddEntryBreakReclamp() {
        // 1h shift: stepping break 60 → 75 re-clamps to 45.
        let d1 = Engine.stepAddEntry(AddEntryDraft(dayOffset: 0, inMin: 660, outMin: 720, breakMin: 60),
                                     field: .breakMin, dir: 1)
        XCTAssertEqual(d1.breakMin, 45)
        // Stepping an unrelated field also re-clamps the break.
        let d2 = Engine.stepAddEntry(AddEntryDraft(dayOffset: 0, inMin: 660, outMin: 720, breakMin: 60),
                                     field: .dayOffset, dir: -1)
        XCTAssertEqual(d2.dayOffset, -1)
        XCTAssertEqual(d2.breakMin, 45)
        // breakMin never below 0.
        XCTAssertEqual(Engine.stepAddEntry(AddEntryDraft(dayOffset: 0, inMin: 600, outMin: 900, breakMin: 0),
                                           field: .breakMin, dir: -1).breakMin, 0)
    }

    // MARK: saveAddEntry segment construction

    func testManualEntryNoBreak() {
        let segs = Engine.manualEntrySegments(dayStart: date(2026, 7, 14),
                                              draft: AddEntryDraft(dayOffset: -1, inMin: 660, outMin: 1080, breakMin: 0))
        XCTAssertEqual(segs, [SegmentSnapshot(isBreak: false,
                                              start: date(2026, 7, 14, 11, 0),
                                              end: date(2026, 7, 14, 18, 0))])
    }

    func testManualEntryCenteredBreak() {
        // Even split: 11:00–18:00, 60m break → offset round((420−60)/2) = 180 → 14:00–15:00.
        let segs = Engine.manualEntrySegments(dayStart: date(2026, 7, 14),
                                              draft: AddEntryDraft(dayOffset: -1, inMin: 660, outMin: 1080, breakMin: 60))
        XCTAssertEqual(segs.count, 3)
        XCTAssertEqual(segs[0], SegmentSnapshot(isBreak: false, start: date(2026, 7, 14, 11, 0), end: date(2026, 7, 14, 14, 0)))
        XCTAssertEqual(segs[1], SegmentSnapshot(isBreak: true, start: date(2026, 7, 14, 14, 0), end: date(2026, 7, 14, 15, 0)))
        XCTAssertEqual(segs[2], SegmentSnapshot(isBreak: false, start: date(2026, 7, 14, 15, 0), end: date(2026, 7, 14, 18, 0)))
        // Net = out − in − break.
        let snap = SessionSnapshot(clockIn: date(2026, 7, 14, 11, 0), clockOut: date(2026, 7, 14, 18, 0), segments: segs)
        XCTAssertEqual(Engine.workDuration(snap, at: date(2026, 7, 14, 18, 0)), 6 * 3600)

        // Odd split rounds like JS: 9:00–16:45, 60m break → offset round(405/2) = 203 → 12:23.
        let odd = Engine.manualEntrySegments(dayStart: date(2026, 7, 14),
                                             draft: AddEntryDraft(dayOffset: -1, inMin: 540, outMin: 1005, breakMin: 60))
        XCTAssertEqual(odd[1].start, date(2026, 7, 14, 12, 23))
        XCTAssertEqual(odd[1].end, date(2026, 7, 14, 13, 23))
        XCTAssertEqual(odd[0].end, odd[1].start)      // contiguous
        XCTAssertEqual(odd[1].end, odd[2].start)
        XCTAssertEqual(odd[2].end, date(2026, 7, 14, 16, 45))
    }

    // MARK: stepPlan

    func testStepPlan() {
        // workMin ∈ [30, 840] step 15
        XCTAssertEqual(Engine.stepPlan(PlanDraft(workMin: 30, breakCount: 1, breakMin: 60), field: .workMin, dir: -1).workMin, 30)
        XCTAssertEqual(Engine.stepPlan(PlanDraft(workMin: 840, breakCount: 1, breakMin: 60), field: .workMin, dir: 1).workMin, 840)
        XCTAssertEqual(Engine.stepPlan(PlanDraft(workMin: 420, breakCount: 1, breakMin: 60), field: .workMin, dir: 1).workMin, 435)
        // breakCount → 0 zeroes breakMin
        let toZero = Engine.stepPlan(PlanDraft(workMin: 420, breakCount: 1, breakMin: 60), field: .breakCount, dir: -1)
        XCTAssertEqual(toZero.breakCount, 0)
        XCTAssertEqual(toZero.breakMin, 0)
        // 0 → 1 defaults breakMin to 30 only when it was 0
        let toOne = Engine.stepPlan(PlanDraft(workMin: 420, breakCount: 0, breakMin: 0), field: .breakCount, dir: 1)
        XCTAssertEqual(toOne.breakCount, 1)
        XCTAssertEqual(toOne.breakMin, 30)
        let keeps = Engine.stepPlan(PlanDraft(workMin: 420, breakCount: 0, breakMin: 45), field: .breakCount, dir: 1)
        XCTAssertEqual(keeps.breakMin, 45)
        // breakCount ≤ 4
        XCTAssertEqual(Engine.stepPlan(PlanDraft(workMin: 420, breakCount: 4, breakMin: 60), field: .breakCount, dir: 1).breakCount, 4)
        // breakMin ∈ [0, 240] step 15
        XCTAssertEqual(Engine.stepPlan(PlanDraft(workMin: 420, breakCount: 1, breakMin: 240), field: .breakMin, dir: 1).breakMin, 240)
        XCTAssertEqual(Engine.stepPlan(PlanDraft(workMin: 420, breakCount: 1, breakMin: 0), field: .breakMin, dir: -1).breakMin, 0)
        XCTAssertEqual(Engine.stepPlan(PlanDraft(workMin: 420, breakCount: 1, breakMin: 60), field: .breakMin, dir: 1).breakMin, 75)
    }

    // Weekly goal in minutes: ±30, clamped [300, 4800] (5h–80h).
    func testStepGoalClamps() {
        XCTAssertEqual(Engine.stepGoal(1950, dir: 1), 1980)
        XCTAssertEqual(Engine.stepGoal(300, dir: -1), 300)
        XCTAssertEqual(Engine.stepGoal(4800, dir: 1), 4800)
        XCTAssertEqual(Engine.stepGoal(310, dir: -1), 300)   // clamps, not just refuses
    }

    // MARK: geofence backdated clock-out

    func testGeoOutTimes() {
        // initial = max(leftAt ?? now, lastSegStart + 5m)
        XCTAssertEqual(Engine.initialGeoOutTime(leftAt: date(2026, 7, 15, 14, 0),
                                                lastSegmentStart: date(2026, 7, 15, 13, 58),
                                                now: date(2026, 7, 15, 14, 32)),
                       date(2026, 7, 15, 14, 3))
        XCTAssertEqual(Engine.initialGeoOutTime(leftAt: date(2026, 7, 15, 14, 30),
                                                lastSegmentStart: date(2026, 7, 15, 9, 0),
                                                now: date(2026, 7, 15, 15, 0)),
                       date(2026, 7, 15, 14, 30))
        XCTAssertEqual(Engine.initialGeoOutTime(leftAt: nil,
                                                lastSegmentStart: date(2026, 7, 15, 9, 0),
                                                now: date(2026, 7, 15, 15, 0)),
                       date(2026, 7, 15, 15, 0))
        // stepped: ±5m clamped to [lastSegStart + 5m, now]
        XCTAssertEqual(Engine.steppedGeoOutTime(current: date(2026, 7, 15, 14, 30), dir: 1,
                                                lastSegmentStart: date(2026, 7, 15, 9, 0),
                                                now: date(2026, 7, 15, 14, 32)),
                       date(2026, 7, 15, 14, 32))
        XCTAssertEqual(Engine.steppedGeoOutTime(current: date(2026, 7, 15, 9, 5), dir: -1,
                                                lastSegmentStart: date(2026, 7, 15, 9, 0),
                                                now: date(2026, 7, 15, 15, 0)),
                       date(2026, 7, 15, 9, 5))
        XCTAssertEqual(Engine.steppedGeoOutTime(current: date(2026, 7, 15, 14, 0), dir: 1,
                                                lastSegmentStart: date(2026, 7, 15, 9, 0),
                                                now: date(2026, 7, 15, 15, 0)),
                       date(2026, 7, 15, 14, 5))
    }

    // confirmGeoOut: segment end = max(chosen, lastSegStart + 60s).
    func testBackdatedSegmentEnd() {
        XCTAssertEqual(Engine.backdatedSegmentEnd(chosen: date(2026, 7, 15, 9, 0, 30),
                                                  lastSegmentStart: date(2026, 7, 15, 9, 0)),
                       date(2026, 7, 15, 9, 1, 0))
        XCTAssertEqual(Engine.backdatedSegmentEnd(chosen: date(2026, 7, 15, 11, 0),
                                                  lastSegmentStart: date(2026, 7, 15, 9, 0)),
                       date(2026, 7, 15, 11, 0))
    }
}
