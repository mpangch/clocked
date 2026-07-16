import Foundation
import Observation
import UserNotifications

// Notification request identifiers.
private let awayPromptID = "awayPrompt"
private let breakNudgeID = "breakNudge"
private let arrivalPromptID = "arrivalPrompt"
private let leftWorkNoticeID = "leftWorkNotice"

// Category / action identifiers.
private let arrivalCategoryID = "ARRIVAL"
private let awayCategoryID = "AWAY"
private let nudgeCategoryID = "NUDGE"
private let clockInActionID = "CLOCK_IN"
private let notNowActionID = "NOT_NOW"
private let geoClockOutActionID = "GEO_CLOCK_OUT"
private let stillWorkingActionID = "STILL_WORKING"
private let takeBreakActionID = "TAKE_BREAK"
private let nudgeLaterActionID = "NUDGE_LATER"

/// App Group flag: a "Yes, clock out…" tap was received but the geo-out sheet
/// may not have a subscriber yet (cold launch). Consumed by refreshOnForeground().
private let pendingGeoOutSheetKey = "pendingGeoOutSheet"

/// Local notifications: geofence arrival/away prompts and the learned break nudge.
@MainActor
final class NotificationManager: NSObject, UNUserNotificationCenterDelegate {
    static let shared = NotificationManager()

    /// Observable state SettingsView reads.
    @Observable
    final class State {
        static let shared = State()
        var authorization: UNAuthorizationStatus = .notDetermined
    }

    private let center = UNUserNotificationCenter.current()

    private override init() {
        super.init()
        center.delegate = self
        registerCategories()
        refreshAuthorizationStatus()
        // TrackerStore posts .trackingDidChange after every mutation.
        NotificationCenter.default.addObserver(
            forName: .trackingDidChange, object: nil, queue: .main
        ) { _ in
            Task { @MainActor in
                NotificationManager.shared.handleTrackingDidChange()
            }
        }
    }

    private func registerCategories() {
        let arrival = UNNotificationCategory(
            identifier: arrivalCategoryID,
            actions: [
                UNNotificationAction(identifier: clockInActionID, title: "Clock In", options: []),
                UNNotificationAction(identifier: notNowActionID, title: "Not now", options: []),
            ],
            intentIdentifiers: []
        )
        let away = UNNotificationCategory(
            identifier: awayCategoryID,
            actions: [
                UNNotificationAction(identifier: geoClockOutActionID, title: "Yes, clock out…", options: [.foreground]),
                UNNotificationAction(identifier: stillWorkingActionID, title: "Still working", options: []),
            ],
            intentIdentifiers: []
        )
        let nudge = UNNotificationCategory(
            identifier: nudgeCategoryID,
            actions: [
                UNNotificationAction(identifier: takeBreakActionID, title: "Break", options: []),
                UNNotificationAction(identifier: nudgeLaterActionID, title: "Later", options: []),
            ],
            intentIdentifiers: []
        )
        center.setNotificationCategories([arrival, away, nudge])
    }

    // MARK: - Authorization

    func requestAuthorization() {
        center.requestAuthorization(options: [.alert, .sound]) { _, _ in
            Task { @MainActor in
                NotificationManager.shared.refreshAuthorizationStatus()
            }
        }
    }

    /// One-shot request at the moment of user intent (geofence configured),
    /// so the M3 prompts aren't silently dropped on a fresh install.
    func requestAuthorizationIfNeeded() {
        center.getNotificationSettings { settings in
            guard settings.authorizationStatus == .notDetermined else { return }
            Task { @MainActor in
                NotificationManager.shared.requestAuthorization()
            }
        }
    }

    func refreshAuthorizationStatus() {
        center.getNotificationSettings { settings in
            let status = settings.authorizationStatus
            Task { @MainActor in
                State.shared.authorization = status
            }
        }
    }

    // MARK: - Tracking changes

    private func handleTrackingDidChange() {
        if TrackerStore.shared.liveShift == nil {
            cancelAwayPrompt()
            cancelBreakNudge()
            // A clock-out consumed any pending "open the geo-out sheet" intent.
            AppGroup.defaults.removeObject(forKey: pendingGeoOutSheetKey)
        } else {
            // Re-evaluate on every mutation; taking a break cancels the nudge
            // because breakCount > 0.
            scheduleBreakNudge()
        }
    }

    // MARK: - Foreground catch-up

    /// Called when the app becomes active.
    func refreshOnForeground() {
        refreshAuthorizationStatus()
        let effects = AwayPromptPolicy.foregroundCatchUp(
            pendingSheetFlag: AppGroup.defaults.bool(forKey: pendingGeoOutSheetKey),
            hasLiveShift: TrackerStore.shared.liveShift != nil,
            leftWorkAt: AppSettings.shared.leftWorkAt,
            awayPrompted: AppSettings.shared.awayPrompted,
            thresholdMinutes: AppSettings.shared.awayThresholdMinutes,
            now: .now
        )
        if effects.consumePendingFlag { AppGroup.defaults.removeObject(forKey: pendingGeoOutSheetKey) }
        // Answering the episode in-app: the scheduled/delivered notification
        // must not stay actionable, or its "Yes, clock out…" reopens the sheet
        // for an episode already declined via "Still working".
        if effects.cancelAwayPrompt { cancelAwayPrompt() }
        if effects.markPrompted { AppSettings.shared.awayPrompted = true }
        if effects.openSheet { NotificationCenter.default.post(name: .openGeoOutSheet, object: nil) }
    }

    // MARK: - Geofence notifications

    // iOS already stamps the app name across the top of every banner, so the
    // title carries the headline and the body the detail — the mockup's own
    // sentences, split at their natural seam.

    /// Enter region while clocked out: "clock in?" with actions.
    func sendArrivalPrompt() {
        let content = UNMutableNotificationContent()
        content.title = "You arrived at Work"
        content.body = "Clock in?"
        content.categoryIdentifier = arrivalCategoryID
        content.sound = .default
        center.add(UNNotificationRequest(identifier: arrivalPromptID, content: content, trigger: nil))
    }

    /// Exit region while clocked in: passive notice, no actions.
    func sendLeftWorkNotice() {
        let content = UNMutableNotificationContent()
        content.title = "You left Work"
        content.body = "Still on the clock."
        content.interruptionLevel = .passive
        center.add(UNNotificationRequest(identifier: leftWorkNoticeID, content: content, trigger: nil))
    }

    /// Away past the threshold: "Are you ready to clock out?" with actions.
    func scheduleAwayPrompt(afterMinutes minutes: Int) {
        scheduleAwayPrompt(fireIn: Double(minutes) * 60, thresholdSeconds: Double(minutes) * 60)
    }

    /// The user changed the away threshold while already away: reschedule the
    /// pending prompt for leftAt + newThreshold (immediately if already past).
    func awayThresholdChanged() {
        guard TrackerStore.shared.liveShift != nil,
              let leftAt = AppSettings.shared.leftWorkAt,
              !AppSettings.shared.awayPrompted else { return }
        let threshold = Double(AppSettings.shared.awayThresholdMinutes) * 60
        let fireIn = max(1, leftAt.addingTimeInterval(threshold).timeIntervalSinceNow)
        scheduleAwayPrompt(fireIn: fireIn, thresholdSeconds: threshold)
    }

    private func scheduleAwayPrompt(fireIn: TimeInterval, thresholdSeconds: TimeInterval) {
        center.removePendingNotificationRequests(withIdentifiers: [awayPromptID])
        let content = UNMutableNotificationContent()
        // Question first — it's the headline; the evidence follows in the body.
        content.title = "Ready to clock out?"
        content.body = "You've been away from Work for \(Fmt.dur(thresholdSeconds))."
        content.categoryIdentifier = awayCategoryID
        content.sound = .default
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: max(1, fireIn), repeats: false)
        center.add(UNNotificationRequest(identifier: awayPromptID, content: content, trigger: trigger))
    }

    func cancelAwayPrompt() {
        center.removePendingNotificationRequests(withIdentifiers: [awayPromptID])
        center.removeDeliveredNotifications(withIdentifiers: [awayPromptID])
    }

    // MARK: - Break nudge

    /// Schedule the learned break nudge for the current shift, if it applies.
    func scheduleBreakNudge() {
        cancelBreakNudge()
        guard let live = TrackerStore.shared.liveSnapshot,
              Engine.breakCount(live) == 0,
              AppSettings.shared.nudgeDismissedForShiftStart != live.clockIn else { return }
        let now = Date.now
        guard let stats = Engine.stats(forWeekday: TimeMath.jsWeekday(now),
                                       history: TrackerStore.shared.historySnapshots(
                                           from: TimeMath.addDays(TimeMath.startOfDay(now), -56),
                                           to: TimeMath.addDays(TimeMath.startOfDay(now), 1)),
                                       reference: now),
              stats.breakFreq >= 0.5,
              let typ = stats.typBreakStartMin else { return }

        let target = TimeMath.startOfDay(now).addingTimeInterval(Double(typ) * 60)
        let trigger: UNNotificationTrigger
        if target > now {
            let comps = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: target)
            trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)
        } else {
            // Typical start already passed — fire now if still inside the −20/+45 window.
            let nowMin = TimeMath.minutesIntoDay(now)
            guard nowMin >= typ - 20 && nowMin <= typ + 45 else { return }
            trigger = UNTimeIntervalNotificationTrigger(timeInterval: 5, repeats: false)
        }

        let content = UNMutableNotificationContent()
        content.title = "Break time?"
        content.body = "You usually step away for ~\(Fmt.dur(Double(TimeMath.round5(stats.typBreakDurMin)) * 60)) around \(Fmt.minToClock(typ))."
        content.categoryIdentifier = nudgeCategoryID
        content.sound = .default
        center.add(UNNotificationRequest(identifier: breakNudgeID, content: content, trigger: trigger))
    }

    func cancelBreakNudge() {
        center.removePendingNotificationRequests(withIdentifiers: [breakNudgeID])
        center.removeDeliveredNotifications(withIdentifiers: [breakNudgeID])
    }

    // MARK: - UNUserNotificationCenterDelegate

    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        [.banner, .sound]
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                didReceive response: UNNotificationResponse) async {
        switch response.actionIdentifier {
        case clockInActionID:
            TrackerStore.shared.clockIn(plan: AppSettings.shared.planDraft)
        case geoClockOutActionID:
            // Reject a STALE action: after "Still working" declined the
            // episode, or re-entry/clock-out cleared it, a leftover delivered
            // notification must not reopen the sheet.
            guard AwayPromptPolicy.acceptGeoClockOut(
                hasLiveShift: TrackerStore.shared.liveShift != nil,
                leftWorkAt: AppSettings.shared.leftWorkAt,
                awayPrompted: AppSettings.shared.awayPrompted
            ) else {
                cancelAwayPrompt()
                break
            }
            // mockup sets geo.prompted when the prompt is answered — don't
            // re-prompt this away episode even if the sheet is cancelled.
            AppSettings.shared.awayPrompted = true
            // Flag covers cold launch, where this post fires before RootView
            // subscribes; consumed at presentation (RootView) or on foreground.
            AppGroup.defaults.set(true, forKey: pendingGeoOutSheetKey)
            NotificationCenter.default.post(name: .openGeoOutSheet, object: nil)
        case stillWorkingActionID:
            // Suppress re-prompting until the next exit (or enter) event.
            AppSettings.shared.awayPrompted = true
        case takeBreakActionID:
            TrackerStore.shared.startBreak()
        case nudgeLaterActionID:
            // Shared per-shift dismissal — also hides the in-app banner.
            AppSettings.shared.nudgeDismissedForShiftStart = TrackerStore.shared.liveSnapshot?.clockIn
        default:
            break // NOT_NOW, plain tap, dismiss → nothing
        }
    }

    /// Consumed by RootView at the moment the geo-out sheet is actually presented,
    /// so a stale flag can't re-open the sheet on a later foreground.
    func consumePendingGeoOutFlag() {
        AppGroup.defaults.removeObject(forKey: pendingGeoOutSheetKey)
    }
}
