import Foundation

// MARK: - Calendar helpers (ports of the mockup's date utilities)

enum TimeMath {
    static let minute: TimeInterval = 60
    static let hour: TimeInterval = 3600

    /// mockup: startOfDay
    static func startOfDay(_ d: Date, calendar: Calendar = .current) -> Date {
        calendar.startOfDay(for: d)
    }

    /// mockup: addDays — calendar-aware (DST safe)
    static func addDays(_ d: Date, _ n: Int, calendar: Calendar = .current) -> Date {
        calendar.date(byAdding: .day, value: n, to: d)!
    }

    /// mockup: monday — start of the Monday-based week containing d
    static func monday(of d: Date, calendar: Calendar = .current) -> Date {
        let sod = startOfDay(d, calendar: calendar)
        let back = (jsWeekday(sod, calendar: calendar) + 6) % 7
        return addDays(sod, -back, calendar: calendar)
    }

    /// JS Date.getDay(): 0 = Sunday … 6 = Saturday
    static func jsWeekday(_ d: Date, calendar: Calendar = .current) -> Int {
        calendar.component(.weekday, from: d) - 1
    }

    /// mockup: dkey — "yyyy-MM-dd" in the local calendar
    static func dayKey(_ d: Date, calendar: Calendar = .current) -> String {
        let c = calendar.dateComponents([.year, .month, .day], from: d)
        return String(format: "%04d-%02d-%02d", c.year!, c.month!, c.day!)
    }

    /// Minutes since local midnight (JS: getHours()*60 + getMinutes())
    static func minutesIntoDay(_ d: Date, calendar: Calendar = .current) -> Int {
        let c = calendar.dateComponents([.hour, .minute], from: d)
        return c.hour! * 60 + c.minute!
    }

    /// First day of the month `offset` months away from the month containing d
    static func firstOfMonth(containing d: Date, offset: Int = 0, calendar: Calendar = .current) -> Date {
        let comps = calendar.dateComponents([.year, .month], from: d)
        let first = calendar.date(from: comps)!
        return calendar.date(byAdding: .month, value: offset, to: first)!
    }

    /// mockup: round5
    static func round5(_ m: Int) -> Int {
        Int((Double(m) / 5).rounded()) * 5
    }

    /// JS Math.round for non-negative values
    static func jsRound(_ x: Double) -> Int {
        Int((x).rounded())
    }

    /// Whole days in [from, to) — mockup: Math.round((to - from) / 24h)
    static func daysBetween(_ from: Date, _ to: Date) -> Int {
        Int((to.timeIntervalSince(from) / (24 * hour)).rounded())
    }

    /// Enumerate day starts d in [from, to) (mockup: for (d = from; d < to; d = addDays(d,1)))
    static func eachDay(from: Date, to: Date, calendar: Calendar = .current) -> [Date] {
        var out: [Date] = []
        var d = from
        while d < to {
            out.append(d)
            d = addDays(d, 1, calendar: calendar)
        }
        return out
    }
}
