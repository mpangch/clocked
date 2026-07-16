import XCTest
@testable import Clocked

/// The wheel pickers commit through absolute-set Engine functions that must
/// enforce exactly the same clamps as the steppers.
final class WheelSetterTests: XCTestCase {
    private let base = Date(timeIntervalSince1970: 1_784_000_000)

    // MARK: clock-in / clock-out clamps

    func testClampedClockIn() {
        let segEnd = base.addingTimeInterval(3600)
        let limit = segEnd.addingTimeInterval(-300)
        // beyond the limit → clamped to first-segment-end − 5m
        XCTAssertEqual(Engine.clampedClockIn(proposed: segEnd, firstSegmentEnd: segEnd, clockOut: base.addingTimeInterval(7200)), limit)
        // any earlier time passes through unclamped (mockup has no lower bound)
        let early = base.addingTimeInterval(-86_400)
        XCTAssertEqual(Engine.clampedClockIn(proposed: early, firstSegmentEnd: segEnd, clockOut: base), early)
        // nil first-segment-end falls back to clockOut
        let out = base.addingTimeInterval(1800)
        XCTAssertEqual(Engine.clampedClockIn(proposed: out, firstSegmentEnd: nil, clockOut: out),
                       out.addingTimeInterval(-300))
    }

    func testClampedClockOut() {
        let lastStart = base
        let floor = base.addingTimeInterval(300)
        XCTAssertEqual(Engine.clampedClockOut(proposed: base.addingTimeInterval(-3600), lastSegmentStart: lastStart), floor)
        let late = base.addingTimeInterval(10 * 3600)
        XCTAssertEqual(Engine.clampedClockOut(proposed: late, lastSegmentStart: lastStart), late)
    }

    func testSteppedMatchesClampedPlusDelta() {
        let segEnd = base.addingTimeInterval(3600)
        let current = base
        XCTAssertEqual(
            Engine.steppedClockIn(current: current, dir: 1, firstSegmentEnd: segEnd, clockOut: segEnd),
            Engine.clampedClockIn(proposed: current.addingTimeInterval(900), firstSegmentEnd: segEnd, clockOut: segEnd)
        )
        XCTAssertEqual(
            Engine.steppedGeoOutTime(current: current.addingTimeInterval(600), dir: -1, lastSegmentStart: current, now: current.addingTimeInterval(1200)),
            Engine.clampedGeoOutTime(proposed: current.addingTimeInterval(300), lastSegmentStart: current, now: current.addingTimeInterval(1200))
        )
    }

    func testClampedGeoOutTime() {
        let lastStart = base
        let now = base.addingTimeInterval(3600)
        XCTAssertEqual(Engine.clampedGeoOutTime(proposed: base, lastSegmentStart: lastStart, now: now),
                       base.addingTimeInterval(300))
        XCTAssertEqual(Engine.clampedGeoOutTime(proposed: now.addingTimeInterval(600), lastSegmentStart: lastStart, now: now),
                       now)
        let mid = base.addingTimeInterval(1800)
        XCTAssertEqual(Engine.clampedGeoOutTime(proposed: mid, lastSegmentStart: lastStart, now: now), mid)
    }

    // MARK: add-entry absolute sets

    func testSetAddEntryClamps() {
        var d = AddEntryDraft(dayOffset: -1, inMin: 11 * 60, outMin: 18 * 60, breakMin: 60)
        // date window [−60, 0]
        XCTAssertEqual(Engine.setAddEntry(d, field: .dayOffset, value: -90).dayOffset, -60)
        XCTAssertEqual(Engine.setAddEntry(d, field: .dayOffset, value: 3).dayOffset, 0)
        // clock-in can't pass out − 30m or go below 0
        XCTAssertEqual(Engine.setAddEntry(d, field: .inMin, value: 23 * 60).inMin, 18 * 60 - 30)
        XCTAssertEqual(Engine.setAddEntry(d, field: .inMin, value: -15).inMin, 0)
        // clock-out can't precede in + 30m or pass 23:45
        XCTAssertEqual(Engine.setAddEntry(d, field: .outMin, value: 0).outMin, 11 * 60 + 30)
        XCTAssertEqual(Engine.setAddEntry(d, field: .outMin, value: 24 * 60).outMin, 24 * 60 - 15)
        // break re-clamps to out − in − 15
        d.inMin = 11 * 60; d.outMin = 12 * 60
        XCTAssertEqual(Engine.setAddEntry(d, field: .breakMin, value: 120).breakMin, 45)
        XCTAssertEqual(Engine.setAddEntry(d, field: .breakMin, value: -30).breakMin, 0)
        // moving clock-in late re-clamps an existing break (cross-field, like stepAddEntry)
        var e = AddEntryDraft(dayOffset: 0, inMin: 9 * 60, outMin: 10 * 60, breakMin: 45)
        e = Engine.setAddEntry(e, field: .inMin, value: 9 * 60 + 30)
        XCTAssertEqual(e.breakMin, 15)
    }

    // MARK: plan absolute sets

    func testSetPlanClamps() {
        var p = PlanDraft(workMin: 7 * 60, breakCount: 1, breakMin: 60)
        XCTAssertEqual(Engine.setPlan(p, field: .workMin, value: 0).workMin, 30)
        XCTAssertEqual(Engine.setPlan(p, field: .workMin, value: 24 * 60).workMin, 14 * 60)
        XCTAssertEqual(Engine.setPlan(p, field: .breakMin, value: 5 * 60).breakMin, 4 * 60)
        // count → 0 zeroes the break time; 0 → n restores the 30m default
        p = Engine.setPlan(p, field: .breakCount, value: 0)
        XCTAssertEqual(p.breakMin, 0)
        p = Engine.setPlan(p, field: .breakCount, value: 2)
        XCTAssertEqual(p.breakCount, 2)
        XCTAssertEqual(p.breakMin, 30)
    }
}
