import SwiftUI

// MARK: - Manual add-entry sheet (mockup: renderAddSheet / stepAdd / saveAddEntry)

struct AddEntrySheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AppModel.self) private var model

    private enum WheelTag { case date, clockIn, clockOut, breakTime }
    /// Which row's inline wheel is open.
    @State private var expandedWheel: WheelTag?

    // mockup: addDraft is module-global — edits survive reopening the sheet.
    private var draft: AddEntryDraft {
        get { model.addEntryDraft }
        nonmutating set { model.addEntryDraft = newValue }
    }

    /// Minutes-since-midnight rendered as a wall-clock COMPONENT date (used by
    /// both the wheel values and their bounds — one construction, one anchor).
    /// Building it with `startOfDay + minutes*60` (absolute seconds) would
    /// drift an hour from the commit side (minutesIntoDay) on DST days.
    private func timeOfDay(_ minutes: Int) -> Date {
        Calendar.current.date(bySettingHour: minutes / 60, minute: minutes % 60, second: 0,
                              of: TimeMath.startOfDay(.now)) ?? .now
    }

    private func timeBinding(_ field: Engine.AddField, minutes: Int) -> Binding<Date> {
        Binding(
            get: { timeOfDay(minutes) },
            set: { draft = Engine.setAddEntry(draft, field: field, value: TimeMath.minutesIntoDay($0)) }
        )
    }

    var body: some View {
        let date = TimeMath.addDays(TimeMath.startOfDay(.now), draft.dayOffset)
        // Breaks are paid: paid hours = clock-out − clock-in, break included.
        let paidMin = max(0, draft.outMin - draft.inMin)

        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Text("Add entry")
                    .font(.system(size: 20, weight: .heavy))
                    .foregroundStyle(Theme.label)
                Text("Manually log a shift you forgot to track")
                    .font(.system(size: 14))
                    .foregroundStyle(Theme.secondary)
                    .padding(.top, 4)
                    .padding(.bottom, 10)

                ExpandableStepperRow(
                    label: "Date",
                    value: draft.dayOffset == 0
                        ? "Today"
                        : Fmt.weekdayShort(date) + ", " + Fmt.dateShort(date),
                    onMinus: { draft = Engine.stepAddEntry(draft, field: .dayOffset, dir: -1) },
                    onPlus: { draft = Engine.stepAddEntry(draft, field: .dayOffset, dir: 1) },
                    tag: WheelTag.date,
                    expanded: $expandedWheel
                ) {
                    WheelDatePicker(
                        mode: .date,
                        minimumDate: TimeMath.addDays(TimeMath.startOfDay(.now), -60),
                        maximumDate: TimeMath.startOfDay(.now),
                        date: Binding(
                            get: { TimeMath.addDays(TimeMath.startOfDay(.now), draft.dayOffset) },
                            set: {
                                let days = TimeMath.daysBetween(TimeMath.startOfDay(.now), TimeMath.startOfDay($0))
                                draft = Engine.setAddEntry(draft, field: .dayOffset, value: days)
                            }
                        )
                    )
                }
                ExpandableStepperRow(
                    label: "Clock in",
                    value: Fmt.minToClock(draft.inMin),
                    onMinus: { draft = Engine.stepAddEntry(draft, field: .inMin, dir: -1) },
                    onPlus: { draft = Engine.stepAddEntry(draft, field: .inMin, dir: 1) },
                    tag: WheelTag.clockIn,
                    expanded: $expandedWheel
                ) {
                    // Dynamic bounds mirror Engine.setAddEntry's clamps: the
                    // wheel must not offer a clock-in the commit would reject
                    // (in ≤ out − 30m), and they move when clock-out moves.
                    WheelDatePicker(mode: .time, minuteInterval: 15,
                                    minimumDate: timeOfDay(0),
                                    maximumDate: timeOfDay(draft.outMin - 30),
                                    date: timeBinding(.inMin, minutes: draft.inMin))
                }
                ExpandableStepperRow(
                    label: "Clock out",
                    value: Fmt.minToClock(draft.outMin),
                    onMinus: { draft = Engine.stepAddEntry(draft, field: .outMin, dir: -1) },
                    onPlus: { draft = Engine.stepAddEntry(draft, field: .outMin, dir: 1) },
                    tag: WheelTag.clockOut,
                    expanded: $expandedWheel
                ) {
                    WheelDatePicker(mode: .time, minuteInterval: 15,
                                    minimumDate: timeOfDay(draft.inMin + 30),
                                    maximumDate: timeOfDay(24 * 60 - 15),
                                    date: timeBinding(.outMin, minutes: draft.outMin))
                }
                ExpandableStepperRow(
                    label: "Paid break",
                    sublabel: "inserted mid-shift",
                    value: Fmt.hm(draft.breakMin),
                    onMinus: { draft = Engine.stepAddEntry(draft, field: .breakMin, dir: -1) },
                    onPlus: { draft = Engine.stepAddEntry(draft, field: .breakMin, dir: 1) },
                    tag: WheelTag.breakTime,
                    expanded: $expandedWheel
                ) {
                    // The break maximum is DYNAMIC — out − in − 15m (mockup /
                    // Engine rule), not the plan card's fixed 4h: the default
                    // 11:00–18:00 entry must offer up to 6h45.
                    WheelDurationPicker(minuteInterval: 15,
                                        range: 0...(draft.outMin - draft.inMin - 15),
                                        minutes: Binding(
                        get: { draft.breakMin },
                        set: { draft = Engine.setAddEntry(draft, field: .breakMin, value: $0) }
                    ))
                }

                Text(.init("Paid hours: **\(Fmt.hm(paidMin))**"))
                    .font(.system(size: 12.5))
                    .foregroundStyle(Theme.tertiary)
                    .frame(maxWidth: .infinity)
                    .padding(.top, 10)

                HStack(spacing: 10) {
                    BigButton(title: "Cancel", background: Theme.inset, foreground: Theme.label) {
                        dismiss()
                    }
                    BigButton(title: "Save entry", background: Theme.green, foreground: .white) {
                        TrackerStore.shared.addManualEntry(draft)
                        dismiss()
                    }
                }
                .padding(.top, 12)
            }
            .padding(20)
        }
        .background(Theme.card)
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }
}
