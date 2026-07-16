import Foundation

/// Pure decision logic for the away-prompt lifecycle (audit defect 1).
///
/// The defect: the in-app foreground catch-up marked an away episode as
/// prompted and opened the sheet, but left the scheduled/delivered
/// "Are you ready to clock out?" notification alive — its "Yes, clock out…"
/// action could later reopen the sheet for an episode the user had already
/// declined via "Still working". These functions decide, from plain values,
/// what each entry point must do, so the rules are exhaustively unit-testable
/// away from UNUserNotificationCenter.
enum AwayPromptPolicy {

    struct CatchUpEffects: Equatable {
        /// Consume the cold-launch pendingGeoOutSheet flag.
        var consumePendingFlag = false
        /// Remove pending AND delivered away prompts — the episode is being
        /// answered in-app, so the notification must not stay actionable.
        var cancelAwayPrompt = false
        /// Mark the current episode prompted (suppresses re-prompts until the
        /// next exit/enter event).
        var markPrompted = false
        var openSheet = false

        static let none = CatchUpEffects()
    }

    /// App became active: decide the foreground catch-up behavior.
    static func foregroundCatchUp(pendingSheetFlag: Bool,
                                  hasLiveShift: Bool,
                                  leftWorkAt: Date?,
                                  awayPrompted: Bool,
                                  thresholdMinutes: Int,
                                  now: Date) -> CatchUpEffects {
        // A "Yes, clock out…" tap validated the episode at tap time; honor it.
        if pendingSheetFlag {
            return CatchUpEffects(consumePendingFlag: true, cancelAwayPrompt: true,
                                  markPrompted: false, openSheet: true)
        }
        // In-app equivalent of the mockup's tick prompt: only for a live,
        // current, still-unanswered away episode past the threshold.
        if hasLiveShift,
           let leftAt = leftWorkAt,
           !awayPrompted,
           now.timeIntervalSince(leftAt) >= Double(thresholdMinutes) * 60 {
            return CatchUpEffects(consumePendingFlag: false, cancelAwayPrompt: true,
                                  markPrompted: true, openSheet: true)
        }
        return .none
    }

    /// "Yes, clock out…" notification action: accept only for a live shift
    /// with a current, unanswered away episode. A stale action (episode
    /// declined via "Still working", cleared by re-entry, or ended by clocking
    /// out) must be rejected instead of reopening the sheet.
    static func acceptGeoClockOut(hasLiveShift: Bool,
                                  leftWorkAt: Date?,
                                  awayPrompted: Bool) -> Bool {
        hasLiveShift && leftWorkAt != nil && !awayPrompted
    }
}
