import SwiftUI

/// "When were you done?" — backdated clock-out after leaving the Work geofence.
/// Port of the mockup's renderGeoOut/stepGeoOut/confirmGeoOut.
@MainActor
struct GeoOutSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var chosen: Date

    init() {
        let lastStart = TrackerStore.shared.liveSnapshot?.segments.last?.start ?? .now
        _chosen = State(initialValue: Engine.initialGeoOutTime(
            leftAt: AppSettings.shared.leftWorkAt,
            lastSegmentStart: lastStart,
            now: .now
        ))
    }

    var body: some View {
        Group {
            if let live = TrackerStore.shared.liveSnapshot {
                content(live: live)
            } else {
                notClockedIn
            }
        }
        .presentationDetents([.medium])
        .presentationDragIndicator(.visible)
    }

    private func content(live: SessionSnapshot) -> some View {
        let lastStart = live.segments.last?.start ?? live.clockIn
        return VStack(alignment: .leading, spacing: 0) {
            Text("When were you done?")
                .font(.system(size: 20, weight: .heavy))
                .foregroundStyle(Theme.label)

            Text("You left Work at \(Fmt.time(AppSettings.shared.leftWorkAt ?? .now)) — the clock-out will be backdated.")
                .font(.system(size: 13.5))
                .foregroundStyle(Theme.secondary)
                .padding(.top, 4)

            StepperRow(
                label: "Finished at",
                sublabel: "5-minute steps",
                value: Fmt.time(chosen),
                onMinus: {
                    chosen = Engine.steppedGeoOutTime(current: chosen, dir: -1,
                                                      lastSegmentStart: lastStart, now: .now)
                },
                onPlus: {
                    chosen = Engine.steppedGeoOutTime(current: chosen, dir: 1,
                                                      lastSegmentStart: lastStart, now: .now)
                }
            )
            .padding(.top, 8)

            SummaryRow(key: "Hours worked",
                       value: Fmt.dur(Engine.workDuration(live, at: chosen)),
                       valueColor: Theme.greenD)
            Divider().overlay(Theme.separator)
            SummaryRow(key: "Unpaid breaks",
                       value: Fmt.dur(Engine.breakDuration(live, at: chosen)))

            HStack(spacing: 10) {
                BigButton(title: "Still working",
                          background: Theme.inset,
                          foreground: Theme.label) {
                    // mockup: suppress re-prompting until the next exit/enter.
                    AppSettings.shared.awayPrompted = true
                    dismiss()
                }
                BigButton(title: "Clock Out",
                          background: Theme.red,
                          foreground: .white) {
                    TrackerStore.shared.backdatedClockOut(finishedAt: chosen)
                    dismiss()
                }
            }
            .padding(.top, 14)

            Spacer(minLength: 0)
        }
        .padding(18)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var notClockedIn: some View {
        VStack(spacing: 14) {
            Text("Not clocked in.")
                .font(.system(size: 15))
                .foregroundStyle(Theme.secondary)
            BigButton(title: "Done",
                      background: Theme.inset,
                      foreground: Theme.label) {
                dismiss()
            }
        }
        .padding(18)
    }
}
