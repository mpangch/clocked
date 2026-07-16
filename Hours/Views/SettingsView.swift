import CoreLocation
import SwiftUI
import UserNotifications

/// Third tab — the mockup's Widgets tab becomes Settings on iOS:
/// weekly goal, Work location / geofence, notifications.
@MainActor
struct SettingsView: View {
    var body: some View {
        let settings = AppSettings.shared
        let geoState = GeofenceManager.State.shared

        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Settings")
                        .font(.system(size: 32, weight: .heavy))
                        .foregroundStyle(Theme.label)
                    Text("Goal, location & notifications")
                        .font(.system(size: 15))
                        .foregroundStyle(Theme.secondary)
                }

                goalCard(settings)
                locationCard(settings, geoState)
                notificationsCard

                Text("Widgets: add the Hours widget from the Home Screen gallery — buttons work without opening the app.")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.tertiary)
            }
            .padding(16)
        }
        .background(Theme.bg.ignoresSafeArea())
        .onAppear {
            NotificationManager.shared.refreshAuthorizationStatus()
        }
    }

    // MARK: - Weekly goal

    private func goalCard(_ settings: AppSettings) -> some View {
        Card(title: "Weekly goal") {
            StepperRow(
                label: "Target hours / week",
                sublabel: "drives week, 2-week and month targets",
                value: Fmt.goalHours(settings.weeklyGoalHours),
                onMinus: { stepGoal(-1) },
                onPlus: { stepGoal(1) }
            )
        }
    }

    private func stepGoal(_ dir: Int) {
        AppSettings.shared.weeklyGoalHours =
            Engine.stepGoal(AppSettings.shared.weeklyGoalMinutes, dir: dir) / 60
    }

    // MARK: - Location · Work

    private func locationCard(_ settings: AppSettings, _ geoState: GeofenceManager.State) -> some View {
        Card(title: "Location · Work") {
            // Geofence toggle (mockup geo card row)
            HStack {
                VStack(alignment: .leading, spacing: 1) {
                    Text("Geofence")
                        .font(.system(size: 15, weight: .medium))
                    Text("prompts to clock in when you arrive,\nand to clock out when you leave")
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.tertiary)
                }
                Spacer()
                Toggle("Geofence", isOn: geofenceBinding)
                    .labelsHidden()
                    .tint(Theme.green)
            }
            .padding(.vertical, 9)

            if settings.geofenceEnabled {
                StepperRow(
                    label: "Away threshold",
                    sublabel: "asks \"Are you ready to clock out?\"\nafter you've been gone this long",
                    value: "\(settings.awayThresholdMinutes)m",
                    onMinus: { stepAwayThreshold(-1) },
                    onPlus: { stepAwayThreshold(1) }
                )

                workLocationRow(settings)

                StepperRow(
                    label: "Radius",
                    value: "\(Int(settings.workRadiusMeters))m",
                    onMinus: { stepRadius(-1) },
                    onPlus: { stepRadius(1) }
                )

                if settings.workLatitude != nil && geoState.authorization != .authorizedAlways {
                    Text("Allow \"Always\" location access in iOS Settings for background prompts.")
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.tertiary)
                }
                if let error = geoState.lastError {
                    Text(error)
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.redD)
                }
            }
        }
    }

    private func workLocationRow(_ settings: AppSettings) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 1) {
                if let lat = settings.workLatitude, let lon = settings.workLongitude {
                    Text("Work location set")
                        .font(.system(size: 15, weight: .medium))
                    Text(String(format: "%.5f, %.5f", lat, lon))
                        .font(.system(size: 12))
                        .monospacedDigit()
                        .foregroundStyle(Theme.tertiary)
                } else {
                    Text("No Work location yet")
                        .font(.system(size: 15, weight: .medium))
                }
            }
            Spacer()
            MiniButton(title: settings.workLatitude != nil
                       ? "Update to Current Location"
                       : "Set to Current Location") {
                GeofenceManager.shared.setWorkLocationToCurrent()
            }
        }
        .padding(.vertical, 9)
    }

    private var geofenceBinding: Binding<Bool> {
        Binding(
            get: { AppSettings.shared.geofenceEnabled },
            set: { enabled in
                AppSettings.shared.geofenceEnabled = enabled
                if !enabled { AppSettings.shared.clearAwayState() }
                GeofenceManager.shared.applySettings()
            }
        )
    }

    private func stepAwayThreshold(_ dir: Int) {
        AppSettings.shared.awayThresholdMinutes =
            min(120, max(5, AppSettings.shared.awayThresholdMinutes + dir * 5))
        // Reschedule a pending away prompt that used the old threshold.
        NotificationManager.shared.awayThresholdChanged()
    }

    private func stepRadius(_ dir: Int) {
        AppSettings.shared.workRadiusMeters =
            min(500, max(100, AppSettings.shared.workRadiusMeters + Double(dir) * 50))
        GeofenceManager.shared.applySettings()
    }

    // MARK: - Notifications

    private var notificationsCard: some View {
        Card(title: "Notifications") {
            HStack {
                Text(notificationsAuthorized ? "Notifications enabled" : "Notifications off")
                    .font(.system(size: 15, weight: .medium))
                Spacer()
                if !notificationsAuthorized {
                    MiniButton(title: "Enable notifications") {
                        NotificationManager.shared.requestAuthorization()
                    }
                }
            }
            .padding(.vertical, 4)
        }
    }

    private var notificationsAuthorized: Bool {
        switch NotificationManager.State.shared.authorization {
        case .authorized, .provisional, .ephemeral: return true
        default: return false
        }
    }
}
