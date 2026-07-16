# Clocked audit test outputs — `e5f5da7`

These outputs belong to the independent adversarial audit pinned to commit
`e5f5da7384a83f59ace5c638b80b7150429cf132`.

The product test-suite summary and audit-probe results below were extracted from
Xcode `.xcresult` bundles with `xcrun xcresulttool get test-results ...`.

Important: audit tests whose names describe incorrect behavior are
**defect-reproduction probes**. A `Passed` result means the probe successfully
observed the defect; it does not mean the product behavior is correct.

## Product test suite

Result bundle:

`/Users/mpang/Library/Developer/Xcode/DerivedData/Clocked-eifihzaribceoyflugbfozwkutyd/Logs/Test/Test-Clocked-2026.07.15_21-26-39--0500.xcresult`

Command used for the successful run:

```sh
xcodegen generate
xcodebuild -project Clocked.xcodeproj -scheme Clocked \
  -destination 'platform=iOS Simulator,id=C1382D06-962E-46B0-AAAB-E3E95C03A404' test
```

Extracted summary:

```json
{
  "device": {
    "architecture": "arm64",
    "deviceId": "C1382D06-962E-46B0-AAAB-E3E95C03A404",
    "deviceName": "iPhone 13",
    "modelName": "iPhone 13",
    "osBuildNumber": "22G86",
    "osVersion": "18.6",
    "platform": "iOS Simulator"
  },
  "environmentDescription": "Clocked · Built with macOS 26.3",
  "expectedFailures": 0,
  "failedTests": 0,
  "passedTests": 62,
  "result": "Passed",
  "skippedTests": 0,
  "totalTestCount": 62
}
```

Terminal result:

```text
Test Suite 'All tests' passed.
Executed 62 tests, with 0 failures (0 unexpected).
** TEST SUCCEEDED **
```

## Independent audit probes

All probes compiled the product `Clocked/` and `Shared/` sources into a temporary
audit host and ran on a fresh iPhone 13 / iOS 18.6 simulator named
`Clocked Audit iPhone 13 e5f5da7`. The temporary source harness and simulator
were removed after the audit; the `.xcresult` evidence remains under Xcode's
DerivedData directory.

### Defect-reproduction probes

```text
Passed — testAddEntryClockInWheelOffersOutOfRangeTime()
Duration: 9.942884 seconds
Result bundle: Test-ClockedAuditHarness-2026.07.15_21-39-04--0500.xcresult
Observed: with Clock Out at 6:00 PM, the Clock In wheel offered 7:00 PM;
          committing it snapped the displayed value to 5:30 PM.

Passed — testForegroundAwayCatchupDoesNotCancelScheduledPrompt()
Duration: 0.721736 seconds
Result bundle: Test-ClockedAuditHarness-2026.07.15_21-45-11--0500.xcresult
Observed: foreground away catch-up marked the episode prompted/opened the sheet
          without cancelling the scheduled away-prompt request.

Passed — testStillWorkingLeavesDeliveredAwayPromptActionable()
Duration: 2.281204 seconds
Result bundle: Test-ClockedAuditHarness-2026.07.15_21-45-55--0500.xcresult
Observed: after foreground catch-up and the Still Working state transition,
          the same awayPrompt identifier remained in delivered notifications.
```

Additional directly observed wheel reproductions from the audit run:

```text
AUDIT_PLAN_MAX: selected 14h + 45m; committed/displayed value was 14h 00m.
AUDIT_ADD_BREAK: default 11:00–18:00 entry accepted 5h through the stepper;
                 the expanded duration wheel stopped at 4h.
```

### Correctness probes

```text
Passed — testDayDetailWheelRekeysAcrossMidnight()
Duration: 14.653316 seconds
Result bundle: Test-ClockedAuditHarness-2026.07.15_21-40-28--0500.xcresult
Observed: moving a Jul 14 session's clock-in to Jul 13 moved the day-detail
          sheet to Monday, Jul 13.

Passed — testManualEntryReviewAndCSVEndToEnd()
Duration: 11.907578 seconds
Result bundle: Test-ClockedAuditHarness-2026.07.15_21-40-56--0500.xcresult
Observed review totals: 6h work, 1h break.
Observed CSV row: 2026-07-14,11:00,18:00,60,6.00

Passed — testGrantNotificationsForHostedAudit()
Duration: 9.627803 seconds
Result bundle: Test-ClockedAuditHarness-2026.07.15_21-44-49--0500.xcresult
Observed: the system notification authorization dialog was handled through UI.
```

The core tracking UI was also exercised successfully through:

```text
Clock In → Working → Take Break → On Break → Resume → Working
→ Clock Out confirmation → Cancel
```

## Unverified simulator probe

```text
Failed — testGeofenceExitProducesAwayState()
Result bundle: Test-ClockedAuditHarness-2026.07.15_21-47-35--0500.xcresult
Failure: XCTAssertTrue failed after waiting for "Away from Work".
```

The audit simulator accepted the location move from `41.8781,-87.6298` to
`41.8900,-87.6298`, but Core Location did not deliver a region-exit event within
the 30-second observation window. This was classified as **unverified**, not as
a product finding.

## Release build

```text
Configuration: Release
Destination: iPhone 13, iOS Simulator 18.6, arm64
Widget extension and App Intents metadata: built
Result: ** BUILD SUCCEEDED **
```

## Confirmed findings represented by these outputs

1. Delivered away notification remains actionable after the in-app
   **Still working** decline path.
2. Add Entry's break wheel is hard-limited to four hours even when the stepper
   correctly permits a longer break.
3. Plan and Add Entry wheels expose invalid rows and then visibly snap to an
   Engine-clamped value.

