import CoreLocation
import Foundation
import Observation

/// Identifier for the single monitored "Work" region.
private let workRegionID = "work"

/// Region monitoring around the single "Work" location (M3).
///
/// Mirrors the mockup's simArrive/simLeave behavior with real CoreLocation events:
///   - enter, clocked out  → arrival notification ("clock in?")
///   - enter, clocked in   → silently clear the away state
///   - exit while clocked in → record `leftWorkAt` and schedule the away prompt
@MainActor
final class GeofenceManager: NSObject, CLLocationManagerDelegate {
    static let shared = GeofenceManager()

    /// Observable state SettingsView reads (the manager itself is an NSObject,
    /// so the @Observable surface lives on this nested singleton).
    @Observable
    final class State {
        static let shared = State()
        var authorization: CLAuthorizationStatus = .notDetermined
        var isMonitoring = false
        var lastError: String?
    }

    private let manager = CLLocationManager()
    private var pendingWorkLocationRequest = false

    private override init() {
        super.init()
        manager.delegate = self
        State.shared.authorization = manager.authorizationStatus
    }

    // MARK: - Configuration

    /// Reconcile region monitoring with the current settings. Called on app
    /// foreground, when the geofence toggle/radius changes, and after the work
    /// location is set.
    func applySettings() {
        let settings = AppSettings.shared
        guard settings.geofenceEnabled,
              let lat = settings.workLatitude,
              let lon = settings.workLongitude else {
            stopAllMonitoring()
            NotificationManager.shared.cancelAwayPrompt()
            return
        }

        requestAuthorizationProgressively()
        // The geofence is configured — this is the moment of user intent for
        // the notification prompts too (arrival / away / nudge).
        NotificationManager.shared.requestAuthorizationIfNeeded()

        guard CLLocationManager.isMonitoringAvailable(for: CLCircularRegion.self) else {
            State.shared.isMonitoring = false
            State.shared.lastError = "Region monitoring is not available on this device."
            return
        }

        let center = CLLocationCoordinate2D(latitude: lat, longitude: lon)
        let radius = min(settings.workRadiusMeters, manager.maximumRegionMonitoringDistance)

        // Ensure exactly one monitored region: the "work" circle with current settings.
        var alreadyMonitored = false
        for region in manager.monitoredRegions {
            if let circle = region as? CLCircularRegion,
               circle.identifier == workRegionID,
               circle.center.latitude == center.latitude,
               circle.center.longitude == center.longitude,
               circle.radius == radius {
                alreadyMonitored = true
            } else {
                manager.stopMonitoring(for: region)
            }
        }
        if !alreadyMonitored {
            let region = CLCircularRegion(center: center, radius: radius, identifier: workRegionID)
            region.notifyOnEntry = true
            region.notifyOnExit = true
            manager.startMonitoring(for: region)
        }
        // Region monitoring only delivers background events with Always
        // authorization — don't report a working-looking geofence without it.
        State.shared.isMonitoring = manager.authorizationStatus == .authorizedAlways
    }

    /// Settings action: capture the current position as the Work location.
    func setWorkLocationToCurrent() {
        State.shared.lastError = nil
        pendingWorkLocationRequest = true
        if manager.authorizationStatus == .notDetermined {
            manager.requestWhenInUseAuthorization()   // retried in didChangeAuthorization
        } else {
            manager.requestLocation()
        }
    }

    // MARK: - Helpers

    /// Progressive escalation: notDetermined → When In Use → Always.
    private func requestAuthorizationProgressively() {
        switch manager.authorizationStatus {
        case .notDetermined:
            manager.requestWhenInUseAuthorization()
        case .authorizedWhenInUse:
            manager.requestAlwaysAuthorization()
        default:
            break
        }
    }

    private func stopAllMonitoring() {
        for region in manager.monitoredRegions {
            manager.stopMonitoring(for: region)
        }
        State.shared.isMonitoring = false
    }

    // MARK: - Region event handling (mockup: simArrive / simLeave)

    private func handleEnter() {
        NotificationManager.shared.cancelAwayPrompt()
        AppSettings.shared.clearAwayState()
        // Clocked out → prompt to clock in. Clocked in → silent clear only.
        if TrackerStore.shared.liveShift == nil && AppSettings.shared.geofenceEnabled {
            NotificationManager.shared.sendArrivalPrompt()
        }
    }

    private func handleExit() {
        guard AppSettings.shared.geofenceEnabled,
              TrackerStore.shared.liveShift != nil else { return }
        AppSettings.shared.leftWorkAt = Date.now
        AppSettings.shared.awayPrompted = false
        NotificationManager.shared.sendLeftWorkNotice()
        NotificationManager.shared.scheduleAwayPrompt(afterMinutes: AppSettings.shared.awayThresholdMinutes)
    }

    // MARK: - CLLocationManagerDelegate
    // The manager is created on the main thread, so callbacks arrive on the
    // main run loop; hop back into MainActor isolation explicitly.

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        MainActor.assumeIsolated {
            State.shared.authorization = status
            // Don't escalate here unconditionally: this callback also fires on
            // startup with .notDetermined, and prompting at launch (before the
            // user has set a Work location) is wrong. applySettings() escalates
            // only once the geofence is actually configured.
            if pendingWorkLocationRequest,
               status == .authorizedWhenInUse || status == .authorizedAlways {
                self.manager.requestLocation()
            }
            applySettings()
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        let coordinate = location.coordinate
        MainActor.assumeIsolated {
            guard pendingWorkLocationRequest else { return }
            pendingWorkLocationRequest = false
            AppSettings.shared.workLatitude = coordinate.latitude
            AppSettings.shared.workLongitude = coordinate.longitude
            applySettings()
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        let message = error.localizedDescription
        MainActor.assumeIsolated {
            pendingWorkLocationRequest = false
            State.shared.lastError = message
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager,
                                     monitoringDidFailFor region: CLRegion?,
                                     withError error: Error) {
        let message = error.localizedDescription
        MainActor.assumeIsolated {
            State.shared.isMonitoring = false
            State.shared.lastError = message
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didEnterRegion region: CLRegion) {
        guard region.identifier == workRegionID else { return }
        MainActor.assumeIsolated { handleEnter() }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didExitRegion region: CLRegion) {
        guard region.identifier == workRegionID else { return }
        MainActor.assumeIsolated { handleExit() }
    }
}
