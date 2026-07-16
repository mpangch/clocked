import Foundation

// MARK: - String formatting (exact ports of the mockup's fmt* helpers)

enum Fmt {
    private static func pad(_ n: Int) -> String { String(format: "%02d", n) }

    static let monthsShort = ["Jan", "Feb", "Mar", "Apr", "May", "Jun",
                              "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]
    static let weekdays = ["Sunday", "Monday", "Tuesday", "Wednesday",
                           "Thursday", "Friday", "Saturday"]

    /// mockup fmtTime: "9:41 AM"
    static func time(_ d: Date, calendar: Calendar = .current) -> String {
        let c = calendar.dateComponents([.hour, .minute], from: d)
        let h = c.hour!, m = c.minute!
        let ap = h >= 12 ? "PM" : "AM"
        let h12 = h % 12 == 0 ? 12 : h % 12
        return "\(h12):\(pad(m)) \(ap)"
    }

    /// mockup fmtDur: "7h 5m" / "45m" (rounds to nearest minute, clamps at 0)
    static func dur(_ seconds: TimeInterval) -> String {
        let t = Int((max(0, seconds) / 60).rounded())
        let h = t / 60, m = t % 60
        return h > 0 ? "\(h)h \(m)m" : "\(m)m"
    }

    /// mockup fmtHM: minutes → "7h 00m"
    static func hm(_ minutes: Int) -> String {
        "\(minutes / 60)h \(pad(minutes % 60))m"
    }

    /// mockup fmtTimer: "1:05:09" (floors seconds)
    static func timer(_ seconds: TimeInterval) -> String {
        let s = Int(max(0, seconds))
        return "\(s / 3600):\(pad((s / 60) % 60)):\(pad(s % 60))"
    }

    /// mockup fmtH1: "7.5h", "7h" (one decimal, trailing .0 stripped).
    /// JS toFixed rounds decimal ties up (4.25 → "4.3"); printf %.1f rounds
    /// half-to-even — so round explicitly, half away from zero (inputs ≥ 0).
    static func h1(_ seconds: TimeInterval) -> String {
        let tenths = Int((seconds / 3600 * 10).rounded(.toNearestOrAwayFromZero))
        return tenths % 10 == 0 ? "\(tenths / 10)h" : "\(tenths / 10).\(tenths % 10)h"
    }

    /// mockup minToClock: minutes since midnight → "2:05 PM"
    static func minToClock(_ minutes: Int) -> String {
        let h = minutes / 60
        let ap = h >= 12 ? "PM" : "AM"
        let h12 = h % 12 == 0 ? 12 : h % 12
        return "\(h12):\(pad(minutes % 60)) \(ap)"
    }

    /// mockup fmtDateShort: "Jul 15"
    static func dateShort(_ d: Date, calendar: Calendar = .current) -> String {
        let c = calendar.dateComponents([.month, .day], from: d)
        return "\(monthsShort[c.month! - 1]) \(c.day!)"
    }

    /// mockup fmt24: "14:05"
    static func time24(_ d: Date, calendar: Calendar = .current) -> String {
        let c = calendar.dateComponents([.hour, .minute], from: d)
        return "\(pad(c.hour!)):\(pad(c.minute!))"
    }

    /// "Tuesday"
    static func weekdayName(_ d: Date, calendar: Calendar = .current) -> String {
        weekdays[TimeMath.jsWeekday(d, calendar: calendar)]
    }

    /// "Tue"
    static func weekdayShort(_ d: Date, calendar: Calendar = .current) -> String {
        String(weekdayName(d, calendar: calendar).prefix(3))
    }

    /// Goal display: 32.5 → "32.5h", 32.0 → "32h" (mockup: toFixed(1).replace(/\.0$/,"") + "h")
    static func goalHours(_ hours: Double) -> String {
        var s = String(format: "%.1f", hours)
        if s.hasSuffix(".0") { s = String(s.dropLast(2)) }
        return s + "h"
    }

    /// "Tuesday, Jul 15"
    static func weekdayDate(_ d: Date, calendar: Calendar = .current) -> String {
        "\(weekdayName(d, calendar: calendar)), \(dateShort(d, calendar: calendar))"
    }
}
