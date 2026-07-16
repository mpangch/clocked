import SwiftUI

// MARK: - Manual add-entry sheet (mockup: renderAddSheet / stepAdd / saveAddEntry)

struct AddEntrySheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AppModel.self) private var model

    // mockup: addDraft is module-global — edits survive reopening the sheet.
    private var draft: AddEntryDraft {
        get { model.addEntryDraft }
        nonmutating set { model.addEntryDraft = newValue }
    }

    var body: some View {
        let date = TimeMath.addDays(TimeMath.startOfDay(.now), draft.dayOffset)
        let netMin = max(0, draft.outMin - draft.inMin - draft.breakMin)

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

                StepperRow(
                    label: "Date",
                    value: draft.dayOffset == 0
                        ? "Today"
                        : Fmt.weekdayShort(date) + ", " + Fmt.dateShort(date),
                    onMinus: { draft = Engine.stepAddEntry(draft, field: .dayOffset, dir: -1) },
                    onPlus: { draft = Engine.stepAddEntry(draft, field: .dayOffset, dir: 1) }
                )
                StepperRow(
                    label: "Clock in",
                    value: Fmt.minToClock(draft.inMin),
                    onMinus: { draft = Engine.stepAddEntry(draft, field: .inMin, dir: -1) },
                    onPlus: { draft = Engine.stepAddEntry(draft, field: .inMin, dir: 1) }
                )
                StepperRow(
                    label: "Clock out",
                    value: Fmt.minToClock(draft.outMin),
                    onMinus: { draft = Engine.stepAddEntry(draft, field: .outMin, dir: -1) },
                    onPlus: { draft = Engine.stepAddEntry(draft, field: .outMin, dir: 1) }
                )
                StepperRow(
                    label: "Unpaid break",
                    sublabel: "inserted mid-shift",
                    value: Fmt.hm(draft.breakMin),
                    onMinus: { draft = Engine.stepAddEntry(draft, field: .breakMin, dir: -1) },
                    onPlus: { draft = Engine.stepAddEntry(draft, field: .breakMin, dir: 1) }
                )

                Text(.init("Net hours: **\(Fmt.hm(netMin))**"))
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
