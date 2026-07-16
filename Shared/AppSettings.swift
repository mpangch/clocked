import Foundation
import Observation
import WidgetKit

enum AppGroup {
    static let id = "group.com.osluv.clocked"
    static var defaults: UserDefaults {
        UserDefaults(suiteName: id) ?? .standard
    }
}

/// User settings + geofence prompt state, backed by the App Group UserDefaults
/// so the app, widget, and intents all see the same values.
@Observable
final class AppSettings {
    static let shared = AppSettings()

    @ObservationIgnored private let d: UserDefaults

    var weeklyGoalHours: Double {
        didSet {
            d.set(weeklyGoalHours, forKey: "weeklyGoalHours")
            // The widget's "This week" bar renders against the goal.
            WidgetCenter.shared.reloadAllTimelines()
        }
    }
    var geofenceEnabled: Bool { didSet { d.set(geofenceEnabled, forKey: "geofenceEnabled") } }
    var awayThresholdMinutes: Int { didSet { d.set(awayThresholdMinutes, forKey: "awayThresholdMinutes") } }
    var planDraft: PlanDraft {
        didSet {
            d.set(planDraft.workMin, forKey: "planDraftWorkMin")
            d.set(planDraft.breakCount, forKey: "planDraftBreakCount")
            d.set(planDraft.breakMin, forKey: "planDraftBreakMin")
        }
    }

    // Work geofence location (set from Settings; nil until configured)
    var workLatitude: Double? { didSet { setOptional(workLatitude, "workLatitude") } }
    var workLongitude: Double? { didSet { setOptional(workLongitude, "workLongitude") } }
    var workRadiusMeters: Double { didSet { d.set(workRadiusMeters, forKey: "workRadiusMeters") } }

    // Geofence prompt state (mockup: geo.leftAt / geo.prompted)
    var leftWorkAt: Date? { didSet { setOptional(leftWorkAt.map(\.timeIntervalSince1970), "leftWorkAt") } }
    var awayPrompted: Bool { didSet { d.set(awayPrompted, forKey: "awayPrompted") } }

    /// mockup: nudgeDismissed — keyed by the shift's clock-in so it expires with
    /// the shift, and shared between the in-app banner and the local notification.
    var nudgeDismissedForShiftStart: Date? {
        didSet { setOptional(nudgeDismissedForShiftStart.map(\.timeIntervalSince1970), "nudgeDismissedShiftStart") }
    }

    var weeklyGoalMinutes: Double { weeklyGoalHours * 60 }

    init(defaults: UserDefaults = AppGroup.defaults) {
        d = defaults
        weeklyGoalHours = defaults.object(forKey: "weeklyGoalHours") as? Double ?? 32.5
        geofenceEnabled = defaults.object(forKey: "geofenceEnabled") as? Bool ?? true
        awayThresholdMinutes = defaults.object(forKey: "awayThresholdMinutes") as? Int ?? 15
        planDraft = PlanDraft(
            workMin: defaults.object(forKey: "planDraftWorkMin") as? Int ?? 7 * 60,
            breakCount: defaults.object(forKey: "planDraftBreakCount") as? Int ?? 1,
            breakMin: defaults.object(forKey: "planDraftBreakMin") as? Int ?? 60
        )
        workLatitude = defaults.object(forKey: "workLatitude") as? Double
        workLongitude = defaults.object(forKey: "workLongitude") as? Double
        workRadiusMeters = defaults.object(forKey: "workRadiusMeters") as? Double ?? 150
        leftWorkAt = (defaults.object(forKey: "leftWorkAt") as? Double).map { Date(timeIntervalSince1970: $0) }
        awayPrompted = defaults.object(forKey: "awayPrompted") as? Bool ?? false
        nudgeDismissedForShiftStart = (defaults.object(forKey: "nudgeDismissedShiftStart") as? Double)
            .map { Date(timeIntervalSince1970: $0) }
    }

    /// mockup: any clock event or re-entry clears leftAt/prompt state.
    func clearAwayState() {
        leftWorkAt = nil
        awayPrompted = false
    }

    private func setOptional(_ value: Double?, _ key: String) {
        if let value { d.set(value, forKey: key) } else { d.removeObject(forKey: key) }
    }
}
