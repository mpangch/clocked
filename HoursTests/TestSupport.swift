import Foundation
import XCTest
@testable import Hours

// MARK: - Fixed test environment
//
// Every test runs against a fixed Gregorian calendar in America/Chicago and a
// fixed "today" of Wednesday, July 15 2026, so expectations never depend on
// the machine's clock, locale, or time zone. Every Engine/Fmt/TimeMath call
// that accepts a calendar must receive `testCal`.

let testCal: Calendar = {
    var c = Calendar(identifier: .gregorian)
    c.timeZone = TimeZone(identifier: "America/Chicago")!
    c.locale = Locale(identifier: "en_US_POSIX")
    return c
}()

/// Absolute Date from local wall-clock components in `testCal`.
func date(_ y: Int, _ m: Int, _ d: Int, _ h: Int = 0, _ min: Int = 0, _ sec: Int = 0) -> Date {
    var comps = DateComponents()
    comps.year = y
    comps.month = m
    comps.day = d
    comps.hour = h
    comps.minute = min
    comps.second = sec
    return testCal.date(from: comps)!
}

/// Anchor "today": Wednesday, July 15 2026.
let anchorMidnight = date(2026, 7, 15)
let anchorNoon = date(2026, 7, 15, 12, 0)

// MARK: - Session builders (mirror the mockup's {in, out, segs} objects)

/// Completed session: work / break / work / … / work.
/// Breaks must be ordered and inside [clockIn, clockOut].
func session(_ clockIn: Date, _ clockOut: Date, breaks: [(start: Date, end: Date)] = []) -> SessionSnapshot {
    var segs: [SegmentSnapshot] = []
    var cursor = clockIn
    for b in breaks {
        segs.append(SegmentSnapshot(isBreak: false, start: cursor, end: b.start))
        segs.append(SegmentSnapshot(isBreak: true, start: b.start, end: b.end))
        cursor = b.end
    }
    segs.append(SegmentSnapshot(isBreak: false, start: cursor, end: clockOut))
    return SessionSnapshot(clockIn: clockIn, clockOut: clockOut, segments: segs)
}

/// Completed work-only session.
func workSession(_ clockIn: Date, _ clockOut: Date) -> SessionSnapshot {
    session(clockIn, clockOut)
}

/// Completed session with exactly one break.
func sessionWithBreak(_ clockIn: Date, _ clockOut: Date, breakStart: Date, breakEnd: Date) -> SessionSnapshot {
    session(clockIn, clockOut, breaks: [(breakStart, breakEnd)])
}

/// Live session: single open work segment.
func openWorkSession(_ clockIn: Date) -> SessionSnapshot {
    SessionSnapshot(clockIn: clockIn, clockOut: nil,
                    segments: [SegmentSnapshot(isBreak: false, start: clockIn, end: nil)])
}

/// Live session currently on an open break that started at `breakStart`.
func openBreakSession(_ clockIn: Date, breakStart: Date) -> SessionSnapshot {
    SessionSnapshot(clockIn: clockIn, clockOut: nil, segments: [
        SegmentSnapshot(isBreak: false, start: clockIn, end: breakStart),
        SegmentSnapshot(isBreak: true, start: breakStart, end: nil),
    ])
}

// MARK: - Stats builder

func makeStats(n: Int = 5,
               avgNetMin: Int = 400,
               avgBreakMin: Int = 50,
               breakCount: Int = 1,
               breakFreq: Double = 1.0,
               avgStartMin: Int = 540,
               typBreakStartMin: Int? = 840,
               typBreakDurMin: Int = 50) -> WeekdayStats {
    WeekdayStats(n: n,
                 avgNetMin: avgNetMin,
                 avgBreakMin: avgBreakMin,
                 breakCount: breakCount,
                 breakFreq: breakFreq,
                 avgStartMin: avgStartMin,
                 typBreakStartMin: typBreakStartMin,
                 typBreakDurMin: typBreakDurMin)
}
