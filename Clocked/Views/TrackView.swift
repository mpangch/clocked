import SwiftUI
import SwiftData

// MARK: - Track tab (port of the mockup's renderTrack() / tick())

struct TrackView: View {
    @Environment(AppModel.self) private var model
    /// Only here to trigger re-render when SwiftData changes;
    /// all reads go through TrackerStore snapshots.
    @Query(sort: \Shift.clockIn) private var shifts: [Shift]
    /// Which plan-card duration wheel is open.
    @State private var expandedPlanWheel: Engine.PlanField?

    private var store: TrackerStore { .shared }
    private var settings: AppSettings { .shared }

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let now = context.date
            ScrollView {
                content(now: now)
                    .padding(.horizontal, 18)
                    .padding(.top, 6)
                    .padding(.bottom, 24)
            }
            .background(Theme.bg.ignoresSafeArea())
        }
    }

    // MARK: content

    @ViewBuilder
    private func content(now: Date) -> some View {
        let liveShift = store.liveShift
        let live = liveShift?.snapshot
        let state = Engine.state(live: live)
        let all = store.allSnapshots
        let todayStats = Engine.stats(forWeekday: TimeMath.jsWeekday(now),
                                      history: store.historySnapshots,
                                      reference: now)

        VStack(alignment: .leading, spacing: 0) {
            header(now: now)
                .padding(.bottom, 14)

            nudgeBanner(live: live, state: state, stats: todayStats, now: now)

            ring(live: live, liveShift: liveShift, state: state, stats: todayStats, all: all, now: now)
                .frame(maxWidth: .infinity)
                .padding(.top, 2)
                .padding(.bottom, 10)

            buttonRow(state: state)
                .padding(.top, 2)
                .padding(.bottom, 14)

            if let live {
                chipRow(live: live, liveShift: liveShift, now: now)
                    .padding(.bottom, 14)
            }

            if state == .out {
                planCard(stats: todayStats, now: now)
                    .padding(.bottom, 12)
            }

            weekCard(all: all, now: now)
                .padding(.bottom, 12)

            geoCard(live: live, now: now)
        }
    }

    // MARK: header

    private func header(now: Date) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Clocked")
                .font(.system(size: 32, weight: .heavy))
                .kerning(0.2)
                .foregroundStyle(Theme.label)
            Text(Fmt.weekdayDate(now))
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(Theme.secondary)
        }
        .padding(.horizontal, 2)
    }

    // MARK: nudge banner (forgot-to-clock-out takes precedence over break nudge)

    @ViewBuilder
    private func nudgeBanner(live: SessionSnapshot?, state: TrackState, stats: WeekdayStats?, now: Date) -> some View {
        if let live, Engine.forgotClockOut(live: live, at: now) {
            banner {
                Text(styledMarkdown("Forgot to clock out? You've been on the clock **\(Fmt.dur(now.timeIntervalSince(live.clockIn)))**.",
                                    boldColor: Theme.amberD))
                    .font(.system(size: 14))
                    .foregroundStyle(Theme.label)
                    .frame(maxWidth: .infinity, alignment: .leading)
                nudgeGoButton("Review") { model.activeSheet = .clockOut }
            }
        } else if let stats,
                  Engine.shouldShowBreakNudge(stats: stats,
                                              state: state,
                                              nudgeDismissed: isNudgeDismissed(live: live),
                                              liveBreakCount: live.map(Engine.breakCount) ?? 0,
                                              at: now) {
            banner {
                Text(styledMarkdown("Break time? You usually step away for **~\(Fmt.dur(Double(TimeMath.round5(stats.typBreakDurMin)) * 60))** around **\(Fmt.minToClock(stats.typBreakStartMin ?? 0))**.",
                                    boldColor: Theme.amberD))
                    .font(.system(size: 14))
                    .foregroundStyle(Theme.label)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Button {
                    dismissNudge(live: live)
                } label: {
                    Text("Later")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(Theme.secondary)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 7)
                }
                .buttonStyle(.plain)
                nudgeGoButton("Break") {
                    store.startBreak()
                    dismissNudge(live: live)
                }
            }
        }
    }

    private func banner<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        HStack(spacing: 10) { content() }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(Theme.amberT, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(Theme.amber.opacity(0.35), lineWidth: 1)
            )
            .padding(.bottom, 12)
    }

    private func nudgeGoButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(.white)
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .background(Theme.amber, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    // MARK: progress ring

    private func ring(live: SessionSnapshot?, liveShift: Shift?, state: TrackState,
                      stats: WeekdayStats?, all: [SessionSnapshot], now: Date) -> some View {
        let net = live.map { Engine.workDuration($0, at: now) } ?? 0
        let planned = Engine.plannedWorkDuration(planWorkMin: liveShift?.plannedWorkMinutes, stats: stats)
        let progress = state == .out ? 0 : Engine.ringProgress(netWorked: net, plannedWork: planned)
        let ringColor = state == .onBreak ? Theme.amber : Theme.green

        return ZStack {
            Circle()
                .stroke(Theme.ringTrack, lineWidth: 15)
                .padding(13)
            Circle()
                .trim(from: 0, to: progress)
                .stroke(ringColor, style: StrokeStyle(lineWidth: 15, lineCap: .round))
                .rotationEffect(.degrees(-90))   // start at 12 o'clock
                .padding(13)
                .animation(.easeInOut(duration: 0.6), value: progress)
            ringCenter(live: live, state: state, stats: stats, net: net, planned: planned, all: all, now: now)
                .padding(.horizontal, 30)
        }
        .frame(width: 262, height: 262)
        .contentShape(Circle())
        .onTapGesture {
            if state == .out { clockInNow() }
        }
    }

    @ViewBuilder
    private func ringCenter(live: SessionSnapshot?, state: TrackState, stats: WeekdayStats?,
                            net: TimeInterval, planned: TimeInterval,
                            all: [SessionSnapshot], now: Date) -> some View {
        VStack(spacing: 0) {
            switch state {
            case .out:
                tagText("Ready", color: Theme.greenD)
                Text("Clock In")
                    .font(.system(size: 36, weight: .heavy))
                    .kerning(-0.5)
                    .foregroundStyle(Theme.label)
                    .padding(.top, 6)
                outHint(stats: stats, all: all, now: now)
                    .padding(.top, 4)

            case .working:
                if let live {
                    tagText("● Working", color: Theme.greenD)
                    Text(Fmt.timer(net))
                        .font(.system(size: 44, weight: .heavy))
                        .monospacedDigit()
                        .kerning(-0.5)
                        .foregroundStyle(Theme.label)
                        .padding(.top, 6)
                    Text("since \(Fmt.time(live.clockIn)) · \(Engine.etaText(plannedWork: planned, netWorked: net, at: now))")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(Theme.secondary)
                        .padding(.top, 4)
                }

            case .onBreak:
                if let live, let lastSeg = live.segments.last {
                    tagText("Ⅱ On Break", color: Theme.amberD)
                    Text(Fmt.timer(Engine.segDuration(lastSeg, at: now)))
                        .font(.system(size: 44, weight: .heavy))
                        .monospacedDigit()
                        .kerning(-0.5)
                        .foregroundStyle(Theme.amberD)
                        .padding(.top, 6)
                    Text("unpaid · worked \(Fmt.dur(net)) so far")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(Theme.secondary)
                        .padding(.top, 4)
                }
            }
        }
        .multilineTextAlignment(.center)
    }

    @ViewBuilder
    private func outHint(stats: WeekdayStats?, all: [SessionSnapshot], now: Date) -> some View {
        let todayWork = Engine.dayTotals(on: now, sessions: all, at: now).work
        Group {
            if todayWork > 0 {
                Text(styledMarkdown("Today so far: **\(Fmt.dur(todayWork))**", boldColor: Theme.label))
            } else if let stats {
                Text("You usually start ~\(Fmt.minToClock(stats.avgStartMin))")
            } else {
                Text("No history yet")
            }
        }
        .font(.system(size: 15, weight: .medium))
        .foregroundStyle(Theme.secondary)
    }

    private func tagText(_ text: String, color: Color) -> some View {
        Text(text.uppercased())
            .font(.system(size: 12, weight: .bold))
            .kerning(1.2)
            .foregroundStyle(color)
    }

    // MARK: buttons

    @ViewBuilder
    private func buttonRow(state: TrackState) -> some View {
        HStack(spacing: 10) {
            switch state {
            case .out:
                BigButton(title: "Clock In", background: Theme.green, foreground: .white) {
                    clockInNow()
                }
            case .working:
                BigButton(title: "Take Break", background: Theme.amberT, foreground: Theme.amberD) {
                    // mockup: startBreak also dismisses the nudge for this shift
                    dismissNudge(live: store.liveSnapshot)
                    store.startBreak()
                }
                clockOutButton
            case .onBreak:
                BigButton(title: "Resume Work", background: Theme.green, foreground: .white) {
                    store.resumeWork()
                }
                clockOutButton
            }
        }
    }

    private var clockOutButton: some View {
        BigButton(title: "Clock Out", background: Theme.redT, foreground: Theme.redD) {
            model.activeSheet = .clockOut
        }
    }

    private func clockInNow() {
        store.clockIn(plan: settings.planDraft)
    }

    // MARK: break-nudge dismissal (shared with the local-notification surface)

    /// Dismissed state is keyed by the shift's clock-in, so it expires naturally
    /// when a new shift starts (mockup resets nudgeDismissed on clockIn).
    private func isNudgeDismissed(live: SessionSnapshot?) -> Bool {
        guard let live else { return false }
        return settings.nudgeDismissedForShiftStart == live.clockIn
    }

    private func dismissNudge(live: SessionSnapshot?) {
        settings.nudgeDismissedForShiftStart = live?.clockIn
        NotificationManager.shared.cancelBreakNudge()
    }

    // MARK: chips

    private func chipRow(live: SessionSnapshot, liveShift: Shift?, now: Date) -> some View {
        let breakCount = Engine.breakCount(live)
        return FlowLayout(spacing: 8) {
            ChipView(text: "In **\(Fmt.time(live.clockIn))**")
            ChipView(text: breakCount > 0
                ? "Breaks **\(breakCount)** · **\(Fmt.dur(Engine.breakDuration(live, at: now)))**"
                : "Breaks **\(breakCount)**")
            if let planWork = liveShift?.plannedWorkMinutes {
                let planBreaks = liveShift?.plannedBreakCount ?? 0
                let planBreakMin = liveShift?.plannedBreakMinutes ?? 0
                ChipView(text: planBreaks > 0
                    ? "Plan **\(Fmt.hm(planWork))** + **\(Fmt.dur(Double(planBreakMin) * 60))** break"
                    : "Plan **\(Fmt.hm(planWork))**")
            }
            if let leftAt = settings.leftWorkAt {
                ChipView(text: "Away from Work **\(Fmt.dur(now.timeIntervalSince(leftAt)))**",
                         background: Theme.amberT,
                         foreground: Theme.amberD)
            }
        }
    }

    // MARK: plan card (only when clocked out)

    private func planCard(stats: WeekdayStats?, now: Date) -> some View {
        let draft = settings.planDraft
        let finish = now.addingTimeInterval(Double(draft.workMin + draft.breakMin) * 60)
        return Card(title: "Today’s plan") {
            if let sug = Engine.suggestionText(stats, weekday: TimeMath.jsWeekday(now)) {
                HStack(spacing: 10) {
                    Text(.init(sug))
                        .font(.system(size: 13.5))
                        .foregroundStyle(Theme.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Button {
                        if let stats { settings.planDraft = Engine.planDraft(from: stats) }
                    } label: {
                        Text("Use")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 13)
                            .padding(.vertical, 7)
                            .background(Theme.green, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 11)
                .background(Theme.inset, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
            VStack(spacing: 0) {
                ExpandableStepperRow(label: "Shift length",
                                     sublabel: "hours on the clock",
                                     value: Fmt.hm(draft.workMin),
                                     onMinus: { stepPlan(.workMin, -1) },
                                     onPlus: { stepPlan(.workMin, +1) },
                                     tag: Engine.PlanField.workMin,
                                     expanded: $expandedPlanWheel) {
                    WheelDurationPicker(minuteInterval: 15, range: 30...840, minutes: Binding(
                        get: { settings.planDraft.workMin },
                        set: { settings.planDraft = Engine.setPlan(settings.planDraft, field: .workMin, value: $0) }
                    ))
                }
                Divider().overlay(Theme.separator)
                StepperRow(label: "Breaks",
                           sublabel: "unpaid, won’t clock you out",
                           value: "\(draft.breakCount)",
                           onMinus: { stepPlan(.breakCount, -1) },
                           onPlus: { stepPlan(.breakCount, +1) })
                if draft.breakCount > 0 {
                    Divider().overlay(Theme.separator)
                    ExpandableStepperRow(label: "Break time",
                                         sublabel: "total across breaks",
                                         value: Fmt.hm(draft.breakMin),
                                         onMinus: { stepPlan(.breakMin, -1) },
                                         onPlus: { stepPlan(.breakMin, +1) },
                                         tag: Engine.PlanField.breakMin,
                                         expanded: $expandedPlanWheel) {
                        WheelDurationPicker(minuteInterval: 15, range: 0...240, minutes: Binding(
                            get: { settings.planDraft.breakMin },
                            set: { settings.planDraft = Engine.setPlan(settings.planDraft, field: .breakMin, value: $0) }
                        ))
                    }
                }
            }
            Text(.init("Clock in now → finish around **\(Fmt.time(finish))**"))
                .font(.system(size: 12.5))
                .foregroundStyle(Theme.tertiary)
                .frame(maxWidth: .infinity)
                .multilineTextAlignment(.center)
        }
    }

    private func stepPlan(_ field: Engine.PlanField, _ dir: Int) {
        settings.planDraft = Engine.stepPlan(settings.planDraft, field: field, dir: dir)
    }


    // MARK: this week card

    private func weekCard(all: [SessionSnapshot], now: Date) -> some View {
        let worked = Engine.weekWorked(sessions: all, at: now)
        let goalSeconds = settings.weeklyGoalMinutes * 60
        let need = Engine.goalNeed(worked: worked, goal: goalSeconds)
        return Card(title: "This week") {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(Fmt.dur(worked))
                    .font(.system(size: 22, weight: .heavy))
                    .monospacedDigit()
                    .foregroundStyle(Theme.label)
                Spacer(minLength: 8)
                Text(styledMarkdown(need.text, boldColor: need.met ? Theme.greenD : Theme.amberD))
                    .font(.system(size: 13.5, weight: .semibold))
                    .foregroundStyle(Theme.secondary)
            }
            ProgressBar(progress: goalSeconds > 0 ? worked / goalSeconds : 0)
            Text("Goal \(Fmt.hm(Int(settings.weeklyGoalMinutes))) / week — change it in Review")
                .font(.system(size: 12))
                .foregroundStyle(Theme.tertiary)
        }
    }

    // MARK: geofence card

    private func geoCard(live: SessionSnapshot?, now: Date) -> some View {
        Card(title: "Location · Work") {
            HStack {
                VStack(alignment: .leading, spacing: 1) {
                    Text("Geofence")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(Theme.label)
                    Text("prompts to clock in when you arrive,\nand to clock out when you leave")
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.tertiary)
                }
                Spacer()
                Toggle("", isOn: geofenceBinding)
                    .labelsHidden()
                    .tint(Theme.green)
            }
            .padding(.vertical, 9)

            if settings.geofenceEnabled {
                Divider().overlay(Theme.separator)
                StepperRow(label: "Away threshold",
                           sublabel: "asks \"Are you ready to clock out?\"\nafter you've been gone this long",
                           value: "\(settings.awayThresholdMinutes)m",
                           onMinus: { stepAwayThreshold(-1) },
                           onPlus: { stepAwayThreshold(+1) })
            }

            if let leftAt = settings.leftWorkAt, live != nil {
                Text("Away from Work since \(Fmt.time(leftAt))")
                    .font(.system(size: 12.5))
                    .foregroundStyle(Theme.amberD)
                    .frame(maxWidth: .infinity)
                    .multilineTextAlignment(.center)
            } else if settings.workLatitude == nil {
                Text("Set your Work location in Settings")
                    .font(.system(size: 12.5))
                    .foregroundStyle(Theme.tertiary)
                    .frame(maxWidth: .infinity)
                    .multilineTextAlignment(.center)
            }
        }
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
        settings.awayThresholdMinutes = min(120, max(5, settings.awayThresholdMinutes + dir * 5))
        GeofenceManager.shared.applySettings()
        // If we're already away, the pending prompt was scheduled with the old
        // threshold — move it.
        NotificationManager.shared.awayThresholdChanged()
    }
}

// MARK: - Clock-out confirmation sheet (mockup: requestClockOut / confirmClockOut)

struct ClockOutSheet: View {
    @Environment(\.dismiss) private var dismiss

    private var store: TrackerStore { .shared }

    var body: some View {
        Group {
            if let live = store.liveSnapshot {
                sheetContent(live: live)
            } else {
                // Guard: nothing to confirm — close silently.
                Color.clear.onAppear { dismiss() }
            }
        }
        .presentationDetents([.medium])
        .presentationDragIndicator(.visible)
    }

    private func sheetContent(live: SessionSnapshot) -> some View {
        let now = Date.now
        let weekAfter = Engine.weekWorked(sessions: store.allSnapshots, at: now)
        let goalMinutes = Int(AppSettings.shared.weeklyGoalMinutes)
        return VStack(alignment: .leading, spacing: 0) {
            Text("Clock out?")
                .font(.system(size: 20, weight: .heavy))
                .foregroundStyle(Theme.label)
            Text(Fmt.weekdayDate(now))
                .font(.system(size: 14))
                .foregroundStyle(Theme.secondary)
                .padding(.top, 2)

            VStack(spacing: 0) {
                SummaryRow(key: "Clocked in", value: Fmt.time(live.clockIn))
                Divider().overlay(Theme.separator)
                SummaryRow(key: "Clocking out", value: Fmt.time(now))
                Divider().overlay(Theme.separator)
                SummaryRow(key: "Unpaid breaks",
                           value: "\(Engine.breakCount(live)) · \(Fmt.dur(Engine.breakDuration(live, at: now)))")
                Divider().overlay(Theme.separator)
                SummaryRow(key: "Hours worked",
                           value: Fmt.dur(Engine.workDuration(live, at: now)),
                           valueColor: Theme.greenD)
                Divider().overlay(Theme.separator)
                SummaryRow(key: "Week after this",
                           value: "\(Fmt.dur(weekAfter)) / \(Fmt.hm(goalMinutes))")
            }
            .padding(.top, 8)

            HStack(spacing: 10) {
                BigButton(title: "Cancel", background: Theme.inset, foreground: Theme.label) {
                    dismiss()
                }
                BigButton(title: "Clock Out", background: Theme.red, foreground: .white) {
                    store.clockOut()
                    dismiss()
                }
            }
            .padding(.top, 16)
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

// MARK: - Helpers

/// Parse **bold** markdown and color the bold runs (mockup: .nudge b / .chip b etc.).
private func styledMarkdown(_ markdown: String, boldColor: Color) -> AttributedString {
    var attr = (try? AttributedString(
        markdown: markdown,
        options: AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)
    )) ?? AttributedString(markdown)
    for run in attr.runs {
        if let intent = run.inlinePresentationIntent, intent.contains(.stronglyEmphasized) {
            attr[run.range].foregroundColor = boldColor
        }
    }
    return attr
}

/// Left-aligned wrapping layout for the chips row (mockup .chipRow with flex-wrap).
private struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, rowHeight: CGFloat = 0, maxX: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > 0, x + size.width > maxWidth {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            x += size.width
            maxX = max(maxX, x)
            x += spacing
            rowHeight = max(rowHeight, size.height)
        }
        let width = proposal.width ?? maxX
        return CGSize(width: width, height: subviews.isEmpty ? 0 : y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, rowHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > bounds.minX, x + size.width > bounds.maxX {
                x = bounds.minX
                y += rowHeight + spacing
                rowHeight = 0
            }
            subview.place(at: CGPoint(x: x, y: y), proposal: .unspecified)
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}
