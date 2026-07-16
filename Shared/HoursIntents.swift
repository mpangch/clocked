import Foundation
import AppIntents

// Shared App Intents driving the tracker from widgets, the Live Activity,
// Shortcuts, and Siri. They conform to LiveActivityIntent so perform() runs
// in the app's process — one writer for the SwiftData store.

struct ClockInIntent: AppIntent, LiveActivityIntent {
    static let title: LocalizedStringResource = "Clock In"
    static let description = IntentDescription("Start a new shift.")
    static let openAppWhenRun: Bool = false

    @MainActor
    func perform() async throws -> some IntentResult {
        TrackerStore.shared.clockIn(plan: AppSettings.shared.planDraft)
        return .result()
    }
}

struct StartBreakIntent: AppIntent, LiveActivityIntent {
    static let title: LocalizedStringResource = "Take a Break"
    static let description = IntentDescription("Start an unpaid break without ending the shift.")
    static let openAppWhenRun: Bool = false

    @MainActor
    func perform() async throws -> some IntentResult {
        TrackerStore.shared.startBreak()
        return .result()
    }
}

struct ResumeIntent: AppIntent, LiveActivityIntent {
    static let title: LocalizedStringResource = "Resume Work"
    static let description = IntentDescription("End the current break and resume working.")
    static let openAppWhenRun: Bool = false

    @MainActor
    func perform() async throws -> some IntentResult {
        TrackerStore.shared.resumeWork()
        return .result()
    }
}

struct ClockOutIntent: AppIntent, LiveActivityIntent {
    static let title: LocalizedStringResource = "Clock Out"
    static let description = IntentDescription("End the current shift.")
    static let openAppWhenRun: Bool = false

    @MainActor
    func perform() async throws -> some IntentResult {
        TrackerStore.shared.clockOut()
        return .result()
    }
}
