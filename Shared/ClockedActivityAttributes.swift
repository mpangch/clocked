import Foundation
#if canImport(ActivityKit)
import ActivityKit

struct ClockedActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        /// true while the current segment is an unpaid break
        var isOnBreak: Bool
        /// original clock-in time (for "since 9:41 AM")
        var clockIn: Date
        /// For the working state: `now − net worked so far`, so
        /// Text(timerInterval: netAnchor...far) renders a live net-hours timer.
        var netAnchor: Date
        /// For the break state: start of the current break segment.
        var breakStart: Date?
        /// Net worked, frozen at the moment the break started (for "worked Xh Ym so far").
        var netWorkedAtBreakStart: TimeInterval
    }
}
#endif
