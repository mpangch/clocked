# Clocked: new iPhone installation and maintenance review

Reviewed 2026-11-10, starting at `8831590` on `main`. The maintenance changes and regression tests accompany this report.

## Status

The source review and project-generation check are complete. **The app is not yet build/test verified on Xcode 27.2 or installed on the new phone.**

- The initial working tree was clean; XcodeGen 2.45.4 reproduced the checked-in project without changes.
- No external package dependencies or backend services need updating.
- The app and widget retain iOS 17 as their minimum OS, matching bundle identifiers and the shared `group.com.osluv.clocked` entitlement. Upgrading Xcode does not require raising that minimum.
- Paid-time calculations in Track, Review, goal cards, CSV and widget totals include paid breaks. Work and break segments remain separate for charts and learned statistics.
- SwiftData model fields and the existing store location are unchanged by this review.
- Xcode changed from 26.3 to **27.2 (27B52)** during the review. The Mac runs macOS 26.7.1 and had approximately 206 GiB free.

## Corrections made

1. Manual entries now interpret selected times as local clock readings. Previously, adding elapsed seconds to midnight shifted a 09:00 entry to 10:00 on the spring DST change or 08:00 on the autumn change. Paid duration and centered breaks now use actual elapsed time. Invalid spring clock readings and impossible durations disable Save with an explanation.
2. CSV import now rejects invalid dates instead of normalizing them into another day (for example, February 30), rejects malformed time separators, and accepts a UTF-8 byte-order mark.
3. Restored break starts now use calendar times instead of clock-minute differences. This preserves break timing when a session crosses a DST transition. Learned break notifications use the same calendar helper.
4. Break and Resume clear the away episode, and the notification observer cancels its scheduled/delivered prompt, as required by the current “any clock event” acceptance criterion.
5. The plan chip says breaks are **included**, replacing the misleading “shift + break” copy.
6. Added nine calendar/import regression tests and one store regression test; existing manual-entry tests now pass their fixed calendar explicitly.

The DST corrections intentionally fix the original mockup's elapsed-seconds construction of wall-clock times. Ordinary-day behavior and the paid-break revision remain unchanged.

## Verification and blockers

- `xcodegen generate`: passed, including registration of the new test file.
- `git diff --check`: passed.
- Initial unsigned Release build on Xcode 26.3: failed when Apple's Observation/SwiftData macro server returned malformed responses in this restricted session. CoreSimulator was also inaccessible. This is not a successful application build.
- Release build and core-test compilation attempts after the upgrade: stopped by Xcode's **unaccepted license agreement**, before source validation. Rechecked before committing after the user reported setup complete: `xcrun swiftc` and `xcrun simctl` still exited 69 with the license message. Command-line setup remains unverified; this is not a source-code test failure.
- No unit tests ran successfully in this review. The old audit's passing results are historical evidence only.
- The browser blocked the local mockup URL. Its script and the Swift implementation were inspected directly; no interactive mockup or device UI checks were completed.

## Remaining findings

- `Shared/TrackerStore.swift` still suppresses fetch/save errors with `try?`. A storage failure can therefore look like a successful clock action or restore. This needs a separate persistence-error handling change and failure-injection tests; it was not refactored while native testing was blocked.
- CSV is a summary restore format, not an exact database backup: it skips active sessions, rounds times to minutes, combines multiple breaks into one, and does not include settings or plans. It cannot represent multi-day shifts or disambiguate the repeated hour at autumn DST. Keep the old phone's data until restored totals have been checked.
- Geofence notifications, background widget actions, Live Activities and layout on the new phone still require device checks. Dynamic Island presentation exists in source but was not exercised.

## Finish setup and run checks

1. Open Xcode 27.2. Review and accept its license yourself, then complete any first-launch component installation. Install the iOS 27.2 platform/simulator components if prompted.
2. Run from the repository:

   ```sh
   xcodegen generate
   xcodebuild -version
   xcodebuild -project Clocked.xcodeproj -scheme Clocked -showdestinations
   ```

3. Select an available iPhone simulator in Xcode and choose **Product → Test**. The existing scheme includes `ClockedTests`. For a CLI run, replace `SIMULATOR_UDID` with the simulator ID from the destinations output:

   ```sh
   xcodebuild -project Clocked.xcodeproj -scheme Clocked \
     -destination 'platform=iOS Simulator,id=SIMULATOR_UDID' test
   xcodebuild -project Clocked.xcodeproj -scheme Clocked \
     -configuration Release -destination 'generic/platform=iOS' \
     CODE_SIGNING_ALLOWED=NO build
   ```

## Transfer and install

1. On the old phone, finish any active shift. Use **Settings → Data → Export** for full history; Review's Export exports only the selected period. Save and transfer the CSV. Record the weekly goal, plan defaults, away threshold and Work location settings separately.
2. Connect and trust the new iPhone. Enable **Developer Mode** on it for installation from Xcode.
3. Open `Clocked.xcodeproj`, choose the **Clocked** scheme and the new iPhone as the destination. In Signing & Capabilities, confirm the intended developer team for both Clocked and ClockedWidgets (the project currently specifies **The OSLUV Project**, `9A74XF5B5H`), automatic signing, and the matching App Group. Do not strip the App Group to silence signing errors; the widget needs the same store.
4. Run the app from Xcode. On a fresh install, use **Settings → Data → Import** and compare several day totals and a full weekly total with the old phone. If device transfer already restored history, check it first; minute-based deduplication prevents same-start imports from duplicating shifts.
5. Recheck settings and location/notification permissions on the new phone. Capture Work's current location only while physically at Work.
6. Exercise Clock In → Break → Resume → Clock Out; verify paid time continues through breaks. Test manual entry/editing, CSV re-import deduplication, widget buttons, lock-screen/Dynamic Island controls, and arrive/away/re-entry prompts. Keep the old phone and CSV until these checks pass.

Apple references: [Xcode requirements](https://developer.apple.com/xcode/system-requirements), [running on devices](https://developer.apple.com/documentation/xcode/running-your-app-on-simulated-or-physical-devices), [Developer Mode](https://developer.apple.com/documentation/xcode/enabling-developer-mode-on-a-device).
