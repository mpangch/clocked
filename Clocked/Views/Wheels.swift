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

/// Duration roller ("2h · 45m") in pure SwiftUI. Deliberately NOT
/// UIDatePicker.countDownTimer, which can't rest at 0h 0m (it auto-commits a
/// nonzero duration on open) and famously drops the first spin's valueChanged.
struct WheelDurationPicker: View {
    var minuteInterval: Int = 15
    var maxHours: Int
    @Binding var minutes: Int

    private var minuteRows: [Int] { Array(stride(from: 0, to: 60, by: minuteInterval)) }

    /// Nearest displayable minute row (values off the grid render as the
    /// closest row; the underlying value only changes when the user scrolls).
    private var displayedMinute: Int {
        let m = minutes % 60
        return minuteRows.min(by: { abs($0 - m) < abs($1 - m) }) ?? 0
    }

    var body: some View {
        HStack(spacing: 0) {
            Picker("Hours", selection: Binding(
                get: { min(minutes / 60, maxHours) },
                set: { minutes = $0 * 60 + displayedMinute }
            )) {
                ForEach(0...maxHours, id: \.self) { h in
                    Text("\(h)h").tag(h)
                }
            }
            .pickerStyle(.wheel)

            Picker("Minutes", selection: Binding(
                get: { displayedMinute },
                set: { minutes = (minutes / 60) * 60 + $0 }
            )) {
                ForEach(minuteRows, id: \.self) { m in
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
