import SwiftUI

struct RootView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        TabView(selection: $model.selectedTab) {
            TrackView()
                .tabItem { Label("Track", systemImage: "clock") }
                .tag(AppTab.track)
            ReviewView()
                .tabItem { Label("Review", systemImage: "chart.bar.xaxis") }
                .tag(AppTab.review)
            SettingsView()
                .tabItem { Label("Settings", systemImage: "gearshape") }
                .tag(AppTab.settings)
        }
        .sheet(item: $model.activeSheet) { sheet in
            switch sheet {
            case .clockOut:
                ClockOutSheet()
            case .dayDetail(let day):
                DayDetailSheet(day: day)
            case .addEntry:
                AddEntrySheet()
            case .geoOut:
                GeoOutSheet()
            case .csv(let text, let subtitle):
                CSVExportSheet(text: text, subtitle: subtitle)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .openGeoOutSheet)) { _ in
            // Consume the cold-launch flag here — presenting IS the fulfillment;
            // a stale flag must not re-open the sheet on a later foreground.
            NotificationManager.shared.consumePendingGeoOutFlag()
            model.activeSheet = .geoOut
        }
        .onReceive(NotificationCenter.default.publisher(for: .openClockOutSheet)) { _ in
            model.activeSheet = .clockOut
        }
    }
}
