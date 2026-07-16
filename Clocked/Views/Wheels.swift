import SwiftUI
import UIKit

// MARK: - Wheel pickers

/// Wheel-style UIDatePicker with minute-interval and range clamping.
/// (SwiftUI's DatePicker exposes no minuteInterval, hence the bridge.)
struct WheelDatePicker: UIViewRepresentable {
    var mode: UIDatePicker.Mode = .dateAndTime
    var minuteInterval: Int = 1
    var minimumDate: Date?
    var maximumDate: Date?
    @Binding var date: Date

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIView(context: Context) -> UIDatePicker {
        let picker = UIDatePicker()
        picker.preferredDatePickerStyle = .wheels
        picker.datePickerMode = mode
        picker.minuteInterval = minuteInterval
        picker.addTarget(context.coordinator, action: #selector(Coordinator.changed(_:)), for: .valueChanged)
        // Let the wheel shrink to the sheet's width instead of forcing overflow.
        picker.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        return picker
    }

    func updateUIView(_ picker: UIDatePicker, context: Context) {
        context.coordinator.parent = self
        // Guard against inverted bounds (e.g. floor is 5m after a segment that
        // started 2m ago while max is "now") — UIDatePicker's behavior with
        // min > max is undefined.
        var minD = minimumDate
        var maxD = maximumDate
        if let a = minD, let b = maxD, a > b { maxD = a; minD = a }
        picker.minimumDate = minD
        picker.maximumDate = maxD
        if abs(picker.date.timeIntervalSince(date)) > 0.5 {
            picker.date = date
        }
    }

    final class Coordinator: NSObject {
        var parent: WheelDatePicker
        init(_ parent: WheelDatePicker) { self.parent = parent }

        @objc func changed(_ sender: UIDatePicker) {
            parent.date = sender.date
        }
    }
}

/// Pure domain for a two-column (hours | minutes) duration wheel: it exposes
/// EXACTLY the valid rows for a ClosedRange of total minutes, so boundary
/// hour/minute combinations outside the range are never selectable — the user
/// cannot pick 14h 45m on a 30m…14h wheel and watch it snap to 14h 00m.
struct DurationWheelDomain: Equatable {
    let range: ClosedRange<Int>      // total minutes
    let interval: Int

    var hourValues: [Int] { Array((range.lowerBound / 60)...(range.upperBound / 60)) }

    /// Interval-grid minute rows that keep hour·60+minute inside the range.
    func minuteValues(forHour hour: Int) -> [Int] {
        let rows = stride(from: 0, to: 60, by: interval).filter { range.contains(hour * 60 + $0) }
        // Grid-aligned bounds always leave ≥1 row; keep a safe fallback for
        // degenerate ranges rather than rendering an empty wheel column.
        return rows.isEmpty ? [min(max(range.lowerBound - hour * 60, 0), 59)] : rows
    }

    /// Nearest displayable (hour, minute) for a value — off-grid values render
    /// as the closest valid row without being mutated until the user scrolls.
    func displayed(for totalMinutes: Int) -> (hour: Int, minute: Int) {
        let clamped = min(max(totalMinutes, range.lowerBound), range.upperBound)
        let hour = clamped / 60
        return (hour, nearestMinute(to: clamped % 60, forHour: hour))
    }

    /// Total after the user selects `hour`, keeping the previously displayed
    /// minute where that hour allows it (else the nearest valid row).
    func total(forHour hour: Int, preferredMinute minute: Int) -> Int {
        hour * 60 + nearestMinute(to: minute, forHour: hour)
    }

    private func nearestMinute(to minute: Int, forHour hour: Int) -> Int {
        minuteValues(forHour: hour).min(by: { abs($0 - minute) < abs($1 - minute) }) ?? 0
    }
}

/// Duration roller ("2h · 45m") in pure SwiftUI. Deliberately NOT
/// UIDatePicker.countDownTimer, which can't rest at 0h 0m (it auto-commits a
/// nonzero duration on open) and famously drops the first spin's valueChanged.
/// The rows come from DurationWheelDomain, so only in-range values exist.
struct WheelDurationPicker: View {
    var minuteInterval: Int = 15
    var range: ClosedRange<Int>
    @Binding var minutes: Int

    var body: some View {
        let domain = DurationWheelDomain(range: range, interval: minuteInterval)
        let shown = domain.displayed(for: minutes)
        HStack(spacing: 0) {
            Picker("Hours", selection: Binding(
                get: { shown.hour },
                set: { minutes = domain.total(forHour: $0, preferredMinute: shown.minute) }
            )) {
                ForEach(domain.hourValues, id: \.self) { h in
                    Text("\(h)h").tag(h)
                }
            }
            .pickerStyle(.wheel)

            Picker("Minutes", selection: Binding(
                get: { shown.minute },
                set: { minutes = shown.hour * 60 + $0 }
            )) {
                ForEach(domain.minuteValues(forHour: shown.hour), id: \.self) { m in
                    Text("\(m)m").tag(m)
                }
            }
            .pickerStyle(.wheel)
        }
        .font(.system(size: 17, weight: .semibold))
        .monospacedDigit()
    }
}

// MARK: - Stepper row with a tap-to-expand wheel

/// A StepperRow whose value is tappable: tapping expands an inline wheel
/// below the row (Calendar-app style). One wheel per surface stays open at a
/// time via the shared `expanded` selection — rows identify themselves by
/// `tag`, so expansion state survives list reorders when tags are stable ids.
struct ExpandableStepperRow<Tag: Hashable, Wheel: View>: View {
    var label: String
    var sublabel: String? = nil
    var value: String
    var onMinus: () -> Void
    var onPlus: () -> Void
    var tag: Tag
    @Binding var expanded: Tag?
    @ViewBuilder var wheel: () -> Wheel

    private var isExpanded: Bool { expanded == tag }

    var body: some View {
        VStack(spacing: 0) {
            StepperRow(
                label: label,
                sublabel: sublabel,
                value: value,
                onMinus: onMinus,
                onPlus: onPlus,
                onTapValue: {
                    withAnimation(.snappy(duration: 0.25)) {
                        expanded = isExpanded ? nil : tag
                    }
                },
                valueHighlighted: isExpanded
            )

            if isExpanded {
                wheel()
                    .frame(maxWidth: .infinity)
                    .frame(height: 190)
                    .clipped()
                    .transition(.asymmetric(insertion: .opacity.combined(with: .scale(scale: 0.96, anchor: .top)),
                                            removal: .opacity))
            }
        }
    }
}
