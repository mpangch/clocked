import XCTest
@testable import Clocked

// CSV export (mockup: exportCSV). Period is [from, to) filtered on clockIn;
// live shift appended with "(active)"; final total row; rows sorted by clockIn.
final class CSVTests: XCTestCase {

    private let header = "date,clock_in,clock_out,break_minutes,break_start,paid_hours"

    func testFullExportGoldenString() {
        // Week Mon 2026-07-13 ..< Mon 2026-07-20.
        let a = sessionWithBreak(date(2026, 7, 13, 9, 0), date(2026, 7, 13, 16, 0),
                                 breakStart: date(2026, 7, 13, 12, 0),
                                 breakEnd: date(2026, 7, 13, 12, 30))       // paid 7.00h, brk 30
        let b = workSession(date(2026, 7, 14, 8, 5), date(2026, 7, 14, 14, 35))  // net 6.50h, pads "08:05"
        // Break 12:00:00–12:50:30 = 50.5 min → rounds to 51; net 18570s = 5.16h.
        let c = sessionWithBreak(date(2026, 7, 16, 9, 0), date(2026, 7, 16, 15, 0),
                                 breakStart: date(2026, 7, 16, 12, 0),
                                 breakEnd: date(2026, 7, 16, 12, 50, 30))
        let beforePeriod = workSession(date(2026, 7, 12, 9, 0), date(2026, 7, 12, 17, 0))  // clockIn < from
        let atPeriodEnd = workSession(date(2026, 7, 20, 9, 0), date(2026, 7, 20, 12, 0))   // clockIn ≥ to
        let live = openWorkSession(date(2026, 7, 17, 9, 0))
        let at = date(2026, 7, 17, 11, 15)                                   // live net 2.25h

        // History passed deliberately out of order — output must sort by clockIn.
        let csv = Engine.csv(history: [b, atPeriodEnd, c, beforePeriod, a],
                             live: live,
                             from: date(2026, 7, 13), to: date(2026, 7, 20),
                             at: at, calendar: testCal)
        let expected = [
            header,
            "2026-07-13,09:00,16:00,30,12:00,7.00",
            "2026-07-14,08:05,14:35,0,,6.50",
            "2026-07-16,09:00,15:00,51,12:00,6.00",
            "2026-07-17,09:00,(active),0,,2.25",
            "total,,,,,21.75",   // paid: 7.0 + 6.5 + 6.0 + 2.25 (breaks are paid)
        ].joined(separator: "\n")
        XCTAssertEqual(csv, expected)
    }

    func testEmptyPeriodHasHeaderAndZeroTotal() {
        let outOfRange = [
            workSession(date(2026, 7, 12, 9, 0), date(2026, 7, 12, 17, 0)),
            workSession(date(2026, 7, 20, 9, 0), date(2026, 7, 20, 12, 0)),
        ]
        let csv = Engine.csv(history: outOfRange, live: nil,
                             from: date(2026, 7, 13), to: date(2026, 7, 20),
                             at: date(2026, 7, 19, 12, 0), calendar: testCal)
        XCTAssertEqual(csv, header + "\ntotal,,,,,0.00")
    }

    func testLiveShiftOutsidePeriodExcluded() {
        let a = sessionWithBreak(date(2026, 7, 13, 9, 0), date(2026, 7, 13, 16, 0),
                                 breakStart: date(2026, 7, 13, 12, 0),
                                 breakEnd: date(2026, 7, 13, 12, 30))
        let live = openWorkSession(date(2026, 7, 20, 9, 0))   // clockIn == to → excluded
        let csv = Engine.csv(history: [a], live: live,
                             from: date(2026, 7, 13), to: date(2026, 7, 20),
                             at: date(2026, 7, 20, 10, 0), calendar: testCal)
        let expected = [
            header,
            "2026-07-13,09:00,16:00,30,12:00,7.00",
            "total,,,,,7.00",
        ].joined(separator: "\n")
        XCTAssertEqual(csv, expected)
        XCTAssertFalse(csv.contains("(active)"))
    }
}
