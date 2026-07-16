import XCTest
@testable import Clocked

/// Regressions for the three confirmed defects from the independent audit
/// pinned to e5f5da7 (docs/audit-test-outputs-e5f5da7.md).
final class AuditDefectRegressionTests: XCTestCase {

    // MARK: - Defect 3: wheels must expose exactly the valid domain

    /// Plan shift length: exactly 30m…14h in 15m rows at both boundaries.
    func testPlanShiftLengthDomainBoundaries() {
        let d = DurationWheelDomain(range: 30...840, interval: 15)
        XCTAssertEqual(d.hourValues, Array(0...14))
        XCTAssertEqual(d.minuteValues(forHour: 0), [30, 45])       // no 0h00/0h15
        XCTAssertEqual(d.minuteValues(forHour: 14), [0])           // no 14h15…14h45
        XCTAssertEqual(d.minuteValues(forHour: 7), [0, 15, 30, 45])
        // The audit's AUDIT_PLAN_MAX repro: 14h45 must be unrepresentable —
        // selecting hour 14 with minute 45 previously shown resolves to 14h00.
        XCTAssertEqual(d.total(forHour: 14, preferredMinute: 45), 840)
        XCTAssertEqual(d.displayed(for: 30).hour, 0)
        XCTAssertEqual(d.displayed(for: 30).minute, 30)
        XCTAssertEqual(d.displayed(for: 840).hour, 14)
        XCTAssertEqual(d.displayed(for: 840).minute, 0)
    }

    /// Plan break time: exactly 0…4h in 15m rows.
    func testPlanBreakDomainBoundaries() {
        let d = DurationWheelDomain(range: 0...240, interval: 15)
        XCTAssertEqual(d.hourValues, Array(0...4))
        XCTAssertEqual(d.minuteValues(forHour: 0), [0, 15, 30, 45])
        XCTAssertEqual(d.minuteValues(forHour: 4), [0])
        XCTAssertEqual(d.total(forHour: 4, preferredMinute: 30), 240)
    }

    /// Off-grid values display the nearest row without being mutated
    /// (documented deliberate behavior).
    func testOffGridValueDisplaysNearestRowWithoutMutation() {
        let d = DurationWheelDomain(range: 0...240, interval: 15)
        let shown = d.displayed(for: 55)
        XCTAssertEqual(shown.hour, 0)
        XCTAssertEqual(shown.minute, 45)   // nearest of 0/15/30/45 to 55
        // displayed(for:) is pure — the bound value is only changed by scrolls.
    }

    // MARK: - Defect 2: Add Entry break maximum is dynamic (out − in − 15)

    /// The default 11:00–18:00 entry must allow a 5h break and reach 6h45.
    func testAddEntryDefaultBreakRangeAllowsFiveHours() {
        let draft = AddEntryDraft(dayOffset: -1, inMin: 11 * 60, outMin: 18 * 60, breakMin: 60)
        let upper = draft.outMin - draft.inMin - 15
        XCTAssertEqual(upper, 405)                                  // 6h45, NOT 4h
        let d = DurationWheelDomain(range: 0...upper, interval: 15)
        XCTAssertEqual(d.hourValues, Array(0...6))
        XCTAssertEqual(d.minuteValues(forHour: 6), [0, 15, 30, 45])  // up to 6h45
        // 5h selectable through the wheel domain…
        XCTAssertEqual(d.displayed(for: 300).hour, 5)
        XCTAssertEqual(d.displayed(for: 300).minute, 0)
        XCTAssertEqual(d.total(forHour: 5, preferredMinute: 0), 300)
        // …and through the Engine setter (stepper parity).
        XCTAssertEqual(Engine.setAddEntry(draft, field: .breakMin, value: 300).breakMin, 300)
        XCTAssertEqual(Engine.setAddEntry(draft, field: .breakMin, value: 405).breakMin, 405)
        XCTAssertEqual(Engine.setAddEntry(draft, field: .breakMin, value: 420).breakMin, 405)
    }

    // MARK: - Defect 3: Add Entry time-wheel bounds + cross-field re-clamp

    /// Clock-in wheel bound: 00:00…out−30m; clock-out: in+30m…23:45. The
    /// audit repro (clock-out 6:00 PM, wheel offered 7:00 PM clock-in) must be
    /// outside the offered bounds AND clamped at commit.
    func testAddEntryDynamicBoundsAndCommitClamp() {
        var draft = AddEntryDraft(dayOffset: 0, inMin: 11 * 60, outMin: 18 * 60, breakMin: 0)
        // Bounds the wheels must offer (in minutes since midnight):
        XCTAssertEqual(draft.outMin - 30, 1050)                     // in-max: 17:30
        XCTAssertEqual(draft.inMin + 30, 690)                       // out-min: 11:30
        XCTAssertEqual(24 * 60 - 15, 1425)                          // out-max: 23:45
        // Commit clamp stays the last line of defense: a 19:00 clock-in with
        // an 18:00 clock-out lands on 17:30, never anything later.
        XCTAssertEqual(Engine.setAddEntry(draft, field: .inMin, value: 19 * 60).inMin, 1050)

        // Cross-field: moving clock-out earlier re-clamps an existing break,
        // and the wheel's dynamic range follows.
        draft.breakMin = 300                                        // 5h
        draft = Engine.setAddEntry(draft, field: .outMin, value: 16 * 60)
        XCTAssertEqual(draft.outMin, 16 * 60)
        XCTAssertEqual(draft.breakMin, 285)                         // 16:00−11:00−15m
        let d = DurationWheelDomain(range: 0...(draft.outMin - draft.inMin - 15), interval: 15)
        XCTAssertEqual(d.hourValues.last, 4)
        XCTAssertEqual(d.minuteValues(forHour: 4), [0, 15, 30, 45]) // caps at 4h45
    }

    // MARK: - Defect 1: away-prompt lifecycle

    private let anchor = Date(timeIntervalSince1970: 1_784_000_000)

    /// Foreground catch-up for a live, overdue, unanswered episode must cancel
    /// the pending/delivered notification while marking + opening the sheet.
    func testForegroundCatchUpCancelsPromptForOverdueEpisode() {
        let fx = AwayPromptPolicy.foregroundCatchUp(
            pendingSheetFlag: false, hasLiveShift: true,
            leftWorkAt: anchor.addingTimeInterval(-20 * 60),
            awayPrompted: false, thresholdMinutes: 15, now: anchor
        )
        XCTAssertTrue(fx.cancelAwayPrompt)
        XCTAssertTrue(fx.markPrompted)
        XCTAssertTrue(fx.openSheet)
        XCTAssertFalse(fx.consumePendingFlag)
    }

    /// The cold-launch "Yes" flag path also consumes the notification.
    func testForegroundCatchUpConsumesFlagAndCancelsPrompt() {
        let fx = AwayPromptPolicy.foregroundCatchUp(
            pendingSheetFlag: true, hasLiveShift: true,
            leftWorkAt: anchor.addingTimeInterval(-20 * 60),
            awayPrompted: true, thresholdMinutes: 15, now: anchor
        )
        XCTAssertTrue(fx.consumePendingFlag)
        XCTAssertTrue(fx.cancelAwayPrompt)
        XCTAssertTrue(fx.openSheet)
    }

    /// A declined episode ("Still working" set awayPrompted) must NOT reopen.
    func testForegroundCatchUpDoesNotReopenDeclinedEpisode() {
        let fx = AwayPromptPolicy.foregroundCatchUp(
            pendingSheetFlag: false, hasLiveShift: true,
            leftWorkAt: anchor.addingTimeInterval(-60 * 60),
            awayPrompted: true, thresholdMinutes: 15, now: anchor
        )
        XCTAssertEqual(fx, .none)
    }

    func testForegroundCatchUpUnderThresholdOrWithoutEpisodeDoesNothing() {
        XCTAssertEqual(AwayPromptPolicy.foregroundCatchUp(
            pendingSheetFlag: false, hasLiveShift: true,
            leftWorkAt: anchor.addingTimeInterval(-10 * 60),
            awayPrompted: false, thresholdMinutes: 15, now: anchor), .none)
        XCTAssertEqual(AwayPromptPolicy.foregroundCatchUp(
            pendingSheetFlag: false, hasLiveShift: false,
            leftWorkAt: anchor.addingTimeInterval(-60 * 60),
            awayPrompted: false, thresholdMinutes: 15, now: anchor), .none)
        XCTAssertEqual(AwayPromptPolicy.foregroundCatchUp(
            pendingSheetFlag: false, hasLiveShift: true,
            leftWorkAt: nil,
            awayPrompted: false, thresholdMinutes: 15, now: anchor), .none)
    }

    /// Stale "Yes, clock out…" actions are rejected; a valid current,
    /// unanswered episode is not blocked.
    func testGeoClockOutActionStaleness() {
        // Valid: live shift, current away episode, not yet answered.
        XCTAssertTrue(AwayPromptPolicy.acceptGeoClockOut(
            hasLiveShift: true, leftWorkAt: anchor, awayPrompted: false))
        // Stale: declined via "Still working".
        XCTAssertFalse(AwayPromptPolicy.acceptGeoClockOut(
            hasLiveShift: true, leftWorkAt: anchor, awayPrompted: true))
        // Stale: re-entry cleared the episode.
        XCTAssertFalse(AwayPromptPolicy.acceptGeoClockOut(
            hasLiveShift: true, leftWorkAt: nil, awayPrompted: false))
        // Stale: already clocked out.
        XCTAssertFalse(AwayPromptPolicy.acceptGeoClockOut(
            hasLiveShift: false, leftWorkAt: anchor, awayPrompted: false))
    }
}
