# Getting started with Claude Code

1. Move this folder where you keep projects, `cd` into it, run `git init`.
2. Install prerequisites (once): Xcode 15+, and `brew install xcodegen`.
3. Run `claude` in this folder and paste the prompt below.

---

## Kickoff prompt (paste into Claude Code)

Read CLAUDE.md, then open docs/hour-tracker-mockup.html and read its script block — it is the working reference implementation of all app logic.

Start Milestone 1: generate the Xcode project with XcodeGen (fix project.yml as needed), then implement core tracking (clock in/out, unpaid breaks, plan + learned suggestions), the Review tab (week/2-week/month, weekly goal, day detail with 15-minute edit steppers, delete, manual add), all on SwiftData. Port the aggregation and suggestion math exactly from the mockup and write unit tests for the cases listed in CLAUDE.md's Testing section. Build for an iPhone 13 simulator and make sure tests pass before moving to Milestone 2.

---

## After M1

- M2: interactive small widget + Live Activity (shared App Intents)
- M3: geofence — arrive prompt; away ≥ 15 min → "Are you ready to clock out?" → backdated "When were you done?" sheet
- M4: CSV export, break-nudge notification, side-by-side polish vs the mockup
