import Foundation
import Observation
import SwiftUI

enum ActiveSheet: Identifiable, Equatable {
    case clockOut                       // confirmation before finalizing (mockup: requestClockOut)
    case dayDetail(Date)                // day-start date of the day being inspected
    case addEntry
    case geoOut                         // "When were you done?" backdating sheet
    case csv(text: String, subtitle: String)

    var id: String {
        switch self {
        case .clockOut: return "clockOut"
        case .dayDetail(let d): return "day-\(d.timeIntervalSinceReferenceDate)"
        case .addEntry: return "addEntry"
        case .geoOut: return "geoOut"
        case .csv: return "csv"
        }
    }
}

extension Notification.Name {
    /// Posted by the notification-action handlers to open the backdating sheet.
    static let openGeoOutSheet = Notification.Name("openGeoOutSheet")
    /// Posted to open the clock-out confirmation (forgot-to-clock-out path).
    static let openClockOutSheet = Notification.Name("openClockOutSheet")
}

enum AppTab: Hashable {
    case track, review, settings
}

@MainActor
@Observable
final class AppModel {
    var activeSheet: ActiveSheet?
    var selectedTab: AppTab = .track

    // Review tab state (mockup: rev = { mode, off })
    var reviewMode: ReviewMode = .week
    var reviewOffset = 0    // 0 = current period, negative = past

    /// mockup: addDraft is module-global — edited values survive reopening the sheet.
    var addEntryDraft = AddEntryDraft()
}
