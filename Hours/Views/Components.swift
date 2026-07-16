import SwiftUI

// MARK: - Shared UI building blocks matching the mockup's cards, steppers, buttons.

/// White rounded card (mockup .card) with optional uppercase section title (.card h3).
struct Card<Content: View>: View {
    var title: String?
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let title {
                Text(title.uppercased())
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.secondary)
                    .kerning(0.6)
            }
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(Theme.card)
        .clipShape(RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))
    }
}

/// − value + control (mockup .stepper)
struct StepperControl: View {
    var value: String
    var onMinus: () -> Void
    var onPlus: () -> Void

    var body: some View {
        HStack(spacing: 0) {
            Button(action: onMinus) {
                Text("−").font(.system(size: 20, weight: .semibold))
                    .frame(width: 38, height: 34)
            }
            Text(value)
                .font(.system(size: 14.5, weight: .bold))
                .monospacedDigit()
                .frame(minWidth: 74)
            Button(action: onPlus) {
                Text("+").font(.system(size: 20, weight: .semibold))
                    .frame(width: 38, height: 34)
            }
        }
        .foregroundStyle(Theme.label)
        .buttonStyle(.plain)
        .background(Theme.inset)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}

/// Label (+ small sublabel) with a stepper on the right (mockup .stepRow)
struct StepperRow: View {
    var label: String
    var sublabel: String?
    var value: String
    var onMinus: () -> Void
    var onPlus: () -> Void

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 1) {
                Text(label).font(.system(size: 15, weight: .medium))
                if let sublabel {
                    Text(sublabel)
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.tertiary)
                }
            }
            Spacer()
            StepperControl(value: value, onMinus: onMinus, onPlus: onPlus)
        }
        .padding(.vertical, 9)
    }
}

/// Big rounded action button (mockup .btn)
struct BigButton: View {
    var title: String
    var background: Color
    var foreground: Color
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 16, weight: .bold))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 15)
                .background(background)
                .foregroundStyle(foreground)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}

/// Thin progress bar (mockup .pbar)
struct ProgressBar: View {
    var progress: Double
    var color: Color = Theme.green
    var height: CGFloat = 9

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Theme.inset)
                Capsule().fill(color)
                    .frame(width: max(0, min(1, progress)) * geo.size.width)
            }
        }
        .frame(height: height)
        .animation(.easeInOut(duration: 0.4), value: progress)
    }
}

/// Small rounded chip (mockup .chip). Text supports **bold** markdown.
struct ChipView: View {
    var text: String
    var background: Color = Theme.card
    var foreground: Color = Theme.secondary

    var body: some View {
        Text(.init(text))
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(foreground)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(background)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

/// Key/value row inside sheets (mockup .sumRow)
struct SummaryRow: View {
    var key: String
    var value: String
    var valueColor: Color = Theme.label

    var body: some View {
        HStack {
            Text(key).foregroundStyle(Theme.secondary)
            Spacer()
            Text(value)
                .fontWeight(.bold)
                .monospacedDigit()
                .foregroundStyle(valueColor)
        }
        .font(.system(size: 15))
        .padding(.vertical, 11)
    }
}

/// Small blue tinted action (mockup .minib)
struct MiniButton: View {
    var title: String
    var color: Color = Theme.blue
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 12.5, weight: .bold))
                .foregroundStyle(color)
                .padding(.horizontal, 11)
                .padding(.vertical, 7)
                .background(color.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}
