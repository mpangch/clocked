import AppIntents

/// Exposes the clock intents to Shortcuts and Siri.
struct ClockedShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: ClockInIntent(),
            phrases: ["Clock in with \(.applicationName)"],
            shortTitle: "Clock In",
            systemImageName: "play.circle"
        )
        AppShortcut(
            intent: StartBreakIntent(),
            phrases: ["Take a break with \(.applicationName)"],
            shortTitle: "Take Break",
            systemImageName: "pause.circle"
        )
        AppShortcut(
            intent: ResumeIntent(),
            phrases: ["Resume work with \(.applicationName)"],
            shortTitle: "Resume",
            systemImageName: "play.circle.fill"
        )
        AppShortcut(
            intent: ClockOutIntent(),
            phrases: ["Clock out with \(.applicationName)"],
            shortTitle: "Clock Out",
            systemImageName: "stop.circle"
        )
    }
}
