# Clocked — iOS Time Tracker

Personal hour-tracking app for one user, one job. **The interactive mockup at `docs/hour-tracker-mockup.html` is the source of truth** for UX, copy, layout, and business logic — open it in a browser and click through before writing code. All tracking/aggregation math exists in its `<script>` block; port it faithfully. `docs/ios-implementation-notes.md` maps features to iOS frameworks.

## Target & stack
- iPhone 13 (390×844 pt, notch — no Dynamic Island), iOS 17.0+, light appearance first.
- SwiftUI + SwiftData (persistence), Swift Charts (review charts), WidgetKit + App Intents (interactive widget), ActivityKit (Live Activity), CoreLocation region monitoring + UserNotifications (geofence prompts).
- No backend. App Group `group.com.osluv.clocked` shares the SwiftData store with the widget extension.
- Project generation: XcodeGen (`project.yml` in repo root) — run `xcodegen generate`. Verify/adjust plist and entitlement details; the yml is a starting point.

## Data model (SwiftData)
```swift
@Model final class Shift {
  var clockIn: Date
  var clockOut: Date?          // nil while active
  var plannedWorkMinutes: Int?
  var plannedBreakCount: Int?
  var plannedBreakMinutes: Int?
  @Relationship(deleteRule: .cascade) var segments: [Segment]  // keep ordered by start
}
@Model final class Segment {
  var isBreak: Bool            // false = work, true = unpaid break
  var start: Date
  var end: Date?               // nil = open segment
}
```
Invariants: exactly one open segment while a shift is active; a break never ends the shift; net hours = Σ work segments; break time is excluded everywhere. A shift belongs to the calendar day of `clockIn` (mockup behavior — do not split at midnight for v1).


**Paid-breaks revision (2026-07-15 — overrides the mockup and any conflicting line in this file):** in-shift breaks are **paid**. Paid hours = clock-in → clock-out = Σ work + break segments, and every pay-facing number (day/week/period totals, weekly goal, CSV `paid_hours`, the big timer, ring progress, ETA) uses paid time. For an *unpaid* break the user simply clocks out and clocks back in later — multiple sessions per day are the normal pattern and sum per day. The work/break segmentation remains for the break nudge, learned stats, review detail, and CSV `break_minutes`. The planned "shift length" contains its paid breaks (finish ≈ clock-in + shift length), suggestion spans are paid time, and UI copy reads "Paid break(s)".

Settings (UserDefaults via App Group): `weeklyGoalHours` (Double, default 32.5, range 5–80, 0.5 steps), `geofenceEnabled` (default true), `awayThresholdMinutes` (default 15, range 5–120, 5-min steps), plan draft defaults.

## Core behaviors (acceptance criteria)

### Tracking
- Clock In starts a shift (records the current plan draft as the plan). Take Break / Resume toggle unpaid break segments. Clock Out shows a confirmation sheet: in, out, breaks (count · duration), net worked, week total vs goal — then finalizes.
- Working state shows: net timer (H:MM:SS), "since 〈clock-in〉", ETA "done ~〈time〉" = now + (planned work − net worked), progress ring = net / planned work (fallback: learned weekday average, else 7h). Break state shows break timer and net-so-far; ring turns amber.
- Chips while active: clock-in time, break count/total, plan summary, and "Away from Work 〈duration〉" when outside the geofence.
- Forgot-to-clock-out banner when a shift passes 12h on the clock → opens the clock-out sheet.

### Plan & learned suggestions
- Plan card (only when clocked out): shift length stepper (15m steps, 30m–14h), breaks count (0–4), total break time (15m steps). Footer: "Clock in now → finish around 〈time〉".
- Suggestion engine: per weekday over a rolling 8-week window compute avg net duration, avg start time, break frequency, avg break count, typical first-break start, typical break duration. Show "〈Weekday〉s you usually work 〈X〉, with a ~〈Y〉 break around 〈time〉." + **Use** button that fills the plan draft (round to 5m).
- Break nudge while working: fire when no break taken yet, weekday break frequency ≥ 0.5, and now is within −20/+45 min of the typical break start. Dismissible per shift ("Later"). In-app banner + local notification.

### Review
- Segmented periods: Week / 2 Weeks / Month, with ‹ › navigation (future disabled). Week starts Monday; 2-week periods anchor to a fixed Monday so pages are stable.
- Stat cards: Worked, Breaks, Avg/day (days with any work). Goal card: worked vs target with progress bar and "Need 〈X〉 more to hit goal" / "Goal met · +〈X〉 over". Targets: week = G; 2-week = 2G; month = G × daysInMonth / 7 (pro-rated).
- Chart (Swift Charts): stacked bars — green net work, amber break on top; per-day bars for week/2-week, per-week bars for month; highlight today.
- Day list (newest first): weekday+date, first-in – last-out, session count, net hours, break total. Tap → day detail.
- Day detail sheet: proportional timeline (green work / amber break / gaps), per-session **clock-in and clock-out steppers (15m)** for finished shifts (clamps: in ≤ first-segment-end − 5m; out ≥ last-segment-start + 5m), segment list, Delete session, day totals.
- **Add entry** sheet (＋ in Review): date (up to 60 days back), clock in, clock out (≥ in + 30m), unpaid break total (inserted as one centered break segment). 
- **Export CSV** for the visible period: header `date,clock_in,clock_out,break_minutes,paid_hours`, one row per shift (24h times), active shift as `(active)`, final `total` row. Share via ShareLink/fileExporter.

- Every time/date/duration value behind a stepper (plan shift length & break time, day-detail clock in/out, all four add-entry fields, geo clock-out finish time) is also tappable: it expands an inline wheel picker (wheel pickers; 1m precision for day-detail fixes, 15m for plan/add-entry, 5m for the geo finish time) clamped to the same limits as the steppers.

### Weekly goal
- Shown on Track ("This week" card) and Review; live-updates while clocked in.

### Widgets & Live Activity
- Small square interactive widget (`systemSmall`): state line, today's net hours, context buttons (Start / Break+Stop / Resume+Stop) via App Intents (`ClockInIntent`, `StartBreakIntent`, `ResumeIntent`, `ClockOutIntent` — shared with the app), mini week-progress bar vs goal. Buttons must work without opening the app.
- Live Activity while clocked in: app icon, state ("Working"/"On break"), running timer via `Text(timerInterval:)`, Break/Resume and Stop buttons via the same intents. Lock screen presentation (no Dynamic Island on iPhone 13).
- Expose intents to Shortcuts/Siri.

### Geofence (single "Work" location)
- Region monitoring (CLCircularRegion or CLMonitor). Request Always authorization with clear usage strings.
- **Enter**, clocked out → notification "You arrived at Work — clock in?" with actions Clock In / Not now. Clocked in → clear away state silently.
- **Exit** while clocked in → record `leftAt`, show passive "You left Work" notice. When away ≥ threshold (default **15 min**, user-adjustable — user drives for work, exits are often not end-of-day) → notification **"You've been away from Work for 〈X〉. Are you ready to clock out?"** with actions "Yes, clock out…" / "Still working".
- "Yes" opens the **"When were you done?"** sheet: finish-time stepper (5m steps, default = `leftAt`, clamp between last-segment-start + 5m and now), shows resulting net hours, then **backdates** the clock-out. "Still working" suppresses re-prompting until the next exit (or enter) event.
- Any clock event or re-entry clears `leftAt`/prompt state. Settings card on Track: geofence toggle + away-threshold stepper (hidden when off).

## Design tokens (from mockup)
Light theme. Background `#F2F2F7`, cards `#FFFFFF` (radius 20), insets `#EFEFF3`, separators `#E4E4EA`. Text: primary `#111114`, secondary `#6E6E76`, tertiary `#A6A6AE`. Accents: green `#34C759` (fills/solid buttons), amber `#FF9500`, red `#FF3B30`, blue `#007AFF`; darker text-on-light variants greenD `#1F8A3B`, amberD `#C25E00`, redD `#D70015`. Tinted buttons: 15% accent background + dark-variant label. SF system font, heavy weights for numerals, tabular figures for timers. Tabs: Track / Review / Widgets(→ Settings on iOS; widget preview not needed in-app).

## Testing
Unit-test the ported math against the mockup's behavior (its JS is the reference; it ships with a 30-case verification suite in spirit):
- Segment arithmetic: net/break sums with open segments; multiple sessions per day.
- Aggregations: day totals, week (Mon start), anchored 2-week, month; goal remaining/met including live shift.
- Suggestion stats per weekday: averages, break frequency, typical break start; nudge window edges (−20/+45).
- Edit clamps (in/out steppers), delete, manual add (centered break), backdated geo clock-out (net excludes time after chosen finish).
- CSV: header, per-shift rows, active row, total row.
- ETA and month pro-rated goal math.

## Milestones
1. **M1** Core tracking + plan + suggestions + Review (incl. goal, edit, add) with SwiftData; unit tests green.
2. **M2** Interactive small widget + Live Activity via shared App Intents.
3. **M3** Geofence + notifications (arrive prompt, 15m-away "Are you ready to clock out?" flow with backdating).
4. **M4** CSV export, break-nudge notification, polish pass against the mockup side-by-side on an iPhone 13 simulator.
