import Foundation
#if canImport(ActivityKit)
import ActivityKit
#endif

/// Starts/updates/ends the lock-screen Live Activity to mirror the tracking state.
/// Only ever *invoked* from the app process (all mutations run there, because the
/// shared intents are LiveActivityIntents), but compiled into both targets.
@MainActor
final class LiveActivityManager {
    static let shared = LiveActivityManager()

    func sync(with store: TrackerStore) {
        #if canImport(ActivityKit)
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        let now = Date.now
        guard let live = store.liveSnapshot, let last = live.segments.last else {
            // Clocked out → end all activities.
            for activity in Activity<ClockedActivityAttributes>.activities {
                Task { await activity.end(nil, dismissalPolicy: .immediate) }
            }
            return
        }
        let net = Engine.workDuration(live, at: now)
        let state = ClockedActivityAttributes.ContentState(
            isOnBreak: last.isBreak,
            clockIn: live.clockIn,
            netAnchor: now.addingTimeInterval(-net),
            breakStart: last.isBreak ? last.start : nil,
            netWorkedAtBreakStart: net
        )
        if let activity = Activity<ClockedActivityAttributes>.activities.first {
            Task { await activity.update(ActivityContent(state: state, staleDate: nil)) }
        } else {
            do {
                _ = try Activity.request(
                    attributes: ClockedActivityAttributes(),
                    content: ActivityContent(state: state, staleDate: nil)
                )
            } catch {
                #if DEBUG
                print("LA-DEBUG request failed: \(error)")
                #endif
            }
        }
        #endif
    }
}
