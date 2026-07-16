# Clocked — iOS Implementation Notes

Port plan for the interactive mockup (`hour-tracker-mockup.html`). Target device: iPhone 13 (390×844 pt, notch — no Dynamic Island), light appearance.

## Stack
- **SwiftUI** app, **SwiftData** for persistence (models below), iOS 17+ target (needed for interactive widgets).
- No backend required — all on-device.

## Data model
```swift
@Model class Shift {
  var clockIn: Date
  var clockOut: Date?
  var plannedWorkMinutes: Int?
  var plannedBreakCount: Int?
  var plannedBreakMinutes: Int?
  @Relationship var segments: [Segment]   // ordered
}
@Model class Segment {
  var type: SegType   // .work / .break (unpaid)
  var start: Date
  var end: Date?
}
```
Net hours = sum of `.work` segments. Break = pause that closes the current work segment and opens a `.break` segment — never ends the Shift. Split shifts crossing midnight at 12:00 AM when aggregating (mockup attributes to start date).

## Widget / one-tap controls (the key feature)
- **Interactive Home Screen widget — small (square, `systemSmall`)**: WidgetKit + **App Intents** (`ClockInIntent`, `BreakIntent`, `ResumeIntent`, `ClockOutIntent`). Buttons run without opening the app.
- **Live Activity** (ActivityKit): Lock Screen while clocked in; buttons via the same App Intents. Use `Text(timerInterval:)` so the timer ticks without pushes. iPhone 13 has no Dynamic Island — iOS shows the status-bar indicator instead (mockup shows a green time pill).
- Optional: Shortcuts/Siri get these intents for free ("Hey Siri, take a break").

## Geofence (implemented in mockup, simulated with Arrive/Leave demo buttons)
- CoreLocation **region monitoring** (`CLCircularRegion` around Work, or `CLMonitor` on iOS 17): works in background without continuous GPS.
- **On enter**: if clocked out → local notification with actions (`UNNotificationAction`: "Clock In" / "Not now").
- **On exit**: record `leftAt`; schedule a check after the away threshold (**default 15 min, user-adjustable** — the user drives for work, so exits aren't always the end of the day). If still outside and clocked in → notification "You've been away 15m — done for the day?" with actions.
- "Yes" opens a sheet asking **when they were actually done** (default = time they left) and backdates the clock-out; "Still working" suppresses re-prompts until the next enter/exit cycle.

## Editing & manual entry (implemented in mockup)
- Day detail sheet: per-session **clock-in / clock-out steppers** (15 min), delete session, segment list.
- **Add entry** sheet for untracked shifts: date, in/out, unpaid break (inserted mid-shift).
- "Forgot to clock out" guard: banner after 12h on the clock (geofence usually catches it sooner).

## CSV export (implemented in mockup)
- Export current review period: `date, clock_in, clock_out, break_minutes, net_hours` + total row.
- iOS: generate file, share via `ShareLink` / `fileExporter` (Files, AirDrop, Mail).

## Suggestions ("learn my behavior")
Same heuristic as the mockup — no ML needed at first:
- Per weekday over a rolling 8-week window: avg net duration, avg start time, break frequency, typical break start + length.
- Pre-fill the shift plan from these; "Use suggestion" chip.
- Break nudge: local notification when (working) ∧ (no break yet) ∧ (now within −20/+45 min of typical break start) ∧ (break frequency ≥ 50%).
- Later: swap in a smarter model if heuristics feel dumb; the interface stays the same.

## Review + goal
- Weekly goal stored as user setting (Double, hours; 0.5 steps; default 32.5).
- Targets: week = G, biweek = 2G (anchor biweeks to a fixed Monday), month = G × days/7 (pro-rated).
- "Need Xh more to hit goal" = max(0, target − net worked in period).
- Charts: Swift Charts (stacked bars: work green / unpaid break amber — matches mockup).

## Nice-to-haves after v1
- iCloud sync (SwiftData + CloudKit).
- Multiple work locations / geofences.
- Overtime alerts when past planned shift length.
