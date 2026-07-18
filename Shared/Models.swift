import Foundation
import SwiftData

// MARK: - SwiftData models (shared between app and widget extension via App Group store)

@Model
final class Shift {
    var clockIn: Date
    var clockOut: Date?          // nil while active
    var plannedWorkMinutes: Int?
    var plannedBreakCount: Int?
    var plannedBreakMinutes: Int?
    @Relationship(deleteRule: .cascade, inverse: \Segment.shift)
    var segments: [Segment]

    init(clockIn: Date,
         clockOut: Date? = nil,
         plannedWorkMinutes: Int? = nil,
         plannedBreakCount: Int? = nil,
         plannedBreakMinutes: Int? = nil,
         segments: [Segment] = []) {
        self.clockIn = clockIn
        self.clockOut = clockOut
        self.plannedWorkMinutes = plannedWorkMinutes
        self.plannedBreakCount = plannedBreakCount
        self.plannedBreakMinutes = plannedBreakMinutes
        self.segments = segments
    }

    /// Segments ordered by start (SwiftData relationships are unordered).
    var orderedSegments: [Segment] {
        segments.sorted { $0.start < $1.start }
    }

    var snapshot: SessionSnapshot {
        SessionSnapshot(
            clockIn: clockIn,
            clockOut: clockOut,
            segments: orderedSegments.map {
                SegmentSnapshot(isBreak: $0.isBreak, start: $0.start, end: $0.end)
            }
        )
    }
}

@Model
final class Segment {
    var isBreak: Bool            // false = work, true = paid break
    var start: Date
    var end: Date?               // nil = open segment
    var shift: Shift?

    init(isBreak: Bool, start: Date, end: Date? = nil) {
        self.isBreak = isBreak
        self.start = start
        self.end = end
    }
}
