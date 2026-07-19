import Foundation

// MARK: - Value types the engine operates on (mirrors the mockup's plain JS objects)

struct SegmentSnapshot: Equatable, Hashable {
    var isBreak: Bool            // mockup: t === "b"
    var start: Date              // mockup: s
    var end: Date?               // mockup: e (nil = open)
}

struct SessionSnapshot: Equatable, Hashable {
    var clockIn: Date            // mockup: in
    var clockOut: Date?          // mockup: out (nil = live)
    var segments: [SegmentSnapshot]

    var isLive: Bool { clockOut == nil }
}

enum TrackState: Equatable {
    case out
    case working
    case onBreak
}

// MARK: - Drafts (mockup: planDraft / addDraft)

struct PlanDraft: Equatable, Codable {
    var workMin: Int = 7 * 60
    var breakCount: Int = 1
    var breakMin: Int = 60
}

struct AddEntryDraft: Equatable {
    var dayOffset: Int = -1      // days relative to today (mockup: dayOff, default yesterday)
    var inMin: Int = 11 * 60     // minutes since midnight
    var outMin: Int = 18 * 60
    var breakMin: Int = 60
}

// MARK: - Aggregates

struct DayTotals: Equatable {
    var work: TimeInterval = 0   // seconds
    var brk: TimeInterval = 0
    var first: Date?
    var last: Date?
    var sessionCount: Int = 0

    /// Paid-breaks revision: breaks are PAID, so paid time = work + breaks
    /// (an unpaid pause is a clock-out — its gap is naturally excluded).
    var paid: TimeInterval { work + brk }
}

struct RangeTotals: Equatable {
    var work: TimeInterval = 0
    var brk: TimeInterval = 0
    /// Days with any PAID time (paid-breaks revision) — drives Avg/day.
    var daysWithPaid: Int = 0

    var paid: TimeInterval { work + brk }
}

struct WeekdayStats: Equatable {
    var n: Int                   // sample size (shifts)
    var avgNetMin: Int
    var avgBreakMin: Int
    var breakCount: Int          // rounded average breaks per shift
    var breakFreq: Double        // avg breaks per shift, unrounded
    var avgStartMin: Int         // minutes since midnight
    var typBreakStartMin: Int?   // minutes since midnight, nil if never breaks
    var typBreakDurMin: Int

    /// Paid-breaks revision: the "you usually work…" span and the planned-
    /// shift fallback are paid time (work + paid breaks).
    var avgPaidMin: Int { avgNetMin + avgBreakMin }
}

enum ReviewMode: String, CaseIterable, Equatable {
    case week
    case biweek
    case month

    var title: String {
        switch self {
        case .week: return "Week"
        case .biweek: return "2 Weeks"
        case .month: return "Month"
        }
    }
}
