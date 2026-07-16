# Clocked — external adversarial audit brief

You are auditing an iOS codebase you have never seen before. Trust nothing you read in code comments or docs about the implementation's correctness; verify everything against the spec and by running the code yourself.

## What this is

A personal hour-tracking app (one user, one job) targeting iPhone 13, iOS 17+. SwiftUI + SwiftData persistence, WidgetKit + App Intents (interactive widget), ActivityKit (Live Activity), CoreLocation region monitoring + UserNotifications (geofence prompts). No backend; an App Group shares the store between app and widget.

## The spec, in priority order

1. **docs/hour-tracker-mockup.html** — an interactive HTML mockup. Its `<script>` block is the executable reference implementation for ALL tracking/aggregation math, thresholds, clamps, state transitions, and user-facing copy. Open it in a browser and click through it; read the JS line by line. When in doubt, the mockup's behavior is the truth.
2. **CLAUDE.md** (repo root) — acceptance criteria per feature, data-model invariants, design tokens, testing requirements. Where CLAUDE.md consciously adapts the mockup to iOS — rolling 8-week window for the suggestion stats; the third tab is Settings instead of a widget preview; prompts additionally delivered as local notifications; the single "Work" geofence location is configured in-app — CLAUDE.md wins. For math, string formatting, copy, and thresholds, the mockup wins.
3. **docs/ios-implementation-notes.md** — background reading only.

## Repo map

- `Shared/` — SwiftData models, pure math engine (`Engine`/`TimeMath`/`Fmt`), settings, data controller (`TrackerStore`), App Intents, Live Activity attributes/manager, design tokens. Compiled into BOTH the app and the widget targets.
- `Clocked/` — the app: views (Track / Review / Settings tabs + sheets), geofence + notification managers, app model/sheet routing.
- `ClockedWidgets/` — widget extension: interactive systemSmall widget + lock-screen Live Activity.
- `ClockedTests/` — unit tests (hosted in the app target).
- `project.yml` — XcodeGen manifest; `Clocked.xcodeproj` is generated from it (`xcodegen generate`).

## Toolchain / how to verify

- Xcode 26.x and XcodeGen (`brew install xcodegen`).
- Simulator: create/boot an iPhone 13 if none exists:
  `xcrun simctl create "iPhone 13" com.apple.CoreSimulator.SimDeviceType.iPhone-13 <installed-iOS-runtime>`
- Build + tests:
  `xcodegen generate && xcodebuild -project Clocked.xcodeproj -scheme Clocked -destination 'platform=iOS Simulator,name=iPhone 13,arch=arm64' test`
- Geofence events can be exercised in the simulator: set the Work location in the app's Settings tab, then move the simulated position with `xcrun simctl location <udid> set <lat>,<lon>` to fire real region enter/exit events.
- Location permission: `xcrun simctl privacy <udid> grant location-always com.osluv.clocked`. Notification permission can only be granted by tapping the system dialog.
- To exercise flows that need history (suggestions, Review, nudges), log shifts via the app's "＋ Add entry" sheet (up to 60 days back) or clock in/out directly.
- Screenshots: `xcrun simctl io <udid> screenshot out.png`.

## Your mission (adversarial)

Assume the implementation is wrong until proven otherwise. Hunt for:

1. **Math/behavior divergence from the mockup JS** — rounding semantics, stepper clamps, window edges, period boundaries (Monday-based weeks, anchored 2-week pages, pro-rated month goal), day attribution of shifts, CSV format, suggestion/nudge conditions, ETA/ring math, backdated clock-out clamps.
2. **Data integrity** — any path that can violate the invariants (exactly one open segment while a shift is active; a break never ends a shift; net hours = Σ work segments), or lose/corrupt shifts: edits, deletes, manual adds, backdating, widget-intent writes racing app writes.
3. **State-machine holes across surfaces** — app UI vs widget vs Live Activity vs notifications vs geofence events: stale state, missed reloads, double prompts, prompts suppressed when they shouldn't be, prompt state not cleared on the events the spec says clear it.
4. **Platform correctness** — Swift concurrency/actor misuse, SwiftData pitfalls (cross-process store access, unordered relationships), ActivityKit/WidgetKit lifecycle, CoreLocation authorization and region-monitoring semantics, timezone/DST/midnight edge cases, iOS 17 API misuse.
5. **Tests that lie** — passing tests whose expectations contradict the mockup.
6. **Release safety** — DEBUG-only behavior leaking into release semantics; Info.plist/entitlements/bundle-ID problems.
7. **Spec sweep** — walk every acceptance bullet in CLAUDE.md top to bottom: is each implemented at all?

**Non-findings (do not report):** SwiftUI-native rendering of HTML idioms (system segmented control, sheet chrome, fonts a point off); style/idiom preferences; the 2-week anchor formula `monday(today) − 7d + offset×14d` (it is the spec even though pages shift as weeks pass); CSV emitting the live-shift row after the completed rows (mockup order).

## Report format

For each finding: **severity** (critical/high/medium/low) · **file:line** · one-sentence defect · **spec citation** (mockup line numbers or CLAUDE.md quote) or the platform rule violated · a **concrete repro / failure scenario** · a suggested minimal fix. Rank most-severe first. Separately list: anything you verified as correct that surprised you, and any spec ambiguities you had to resolve (and how). If a category yields nothing, say so explicitly rather than padding.
