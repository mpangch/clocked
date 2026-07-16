import SwiftUI
import SwiftData

@main
struct ClockedApp: App {
    @State private var model = AppModel()
    @Environment(\.scenePhase) private var scenePhase

    init() {
        // Eagerly create the managers so their observers exist even when the
        // process is launched in the background (e.g. for a widget intent).
        _ = NotificationManager.shared
        _ = GeofenceManager.shared
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(model)
                .tint(Theme.green)
                .preferredColorScheme(.light)
        }
        .modelContainer(TrackerStore.shared.container)
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                GeofenceManager.shared.applySettings()
                NotificationManager.shared.refreshOnForeground()
                // Reconcile the Live Activity: mutations that happened while
                // backgrounded (e.g. clock-in from a notification action) can't
                // start one — ActivityKit only allows requests from the
                // foreground or from LiveActivityIntents.
                LiveActivityManager.shared.sync(with: TrackerStore.shared)
            }
        }
    }
}
