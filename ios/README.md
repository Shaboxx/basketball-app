# Offline native basketball workbench

The native target connects the application's original pure Swift models and rule/game engines to a local SwiftUI front end. It contains **20 fictional players across four fictional teams**. Their salaries and rating fields are illustrative inputs, not measurements or model predictions.

The front end supports player search and detail, contract/rating inspection, two-team trade review, a constrained four-role roster builder, an eight-question seeded quiz, and a higher/lower contract game. Trade proposals stay local and require human review. Five-player fixture rosters deliberately produce roster-minimum warnings. The trade engine implements the recorded 2025–26 rules logic, not a certification against the latest CBA.

## Launch on Apple platforms

Use **Xcode 26 or later with Swift 6.2 or later**.

- iOS: open `BasketballOffline.xcodeproj`, choose scheme **BasketballOffline**, select an iOS simulator, and run. A physical device requires your own signing configuration.
- macOS: from the repository root, run `swift run basketball-native`. The package requires macOS 14 or later.

The target has no package dependencies, cloud setup, login, API credentials, external media, or network request path. Its synthetic fixture is defined in `NBATradeMachine/Offline/OfflineFixtures.swift`.

Build the iOS app without device signing:

```bash
xcodebuild -project ios/BasketballOffline.xcodeproj \
  -scheme BasketballOffline -configuration Debug \
  -sdk iphonesimulator -destination 'generic/platform=iOS Simulator' \
  CODE_SIGNING_ALLOWED=NO build
```

## Reproduce the portable core

From the repository root, with Swift 6.2 or later:

```bash
swift test --jobs 2
swift run basketball-native --report
```

On Linux, the command emits the report automatically. On macOS, `--report` selects the noninteractive path. The report records the synthetic pool, generated quiz count, salary-matching example, and a completed constrained draft. See [the captured deterministic output](OfflineExample.json).

The verified Linux build used `swift:6.2-noble` with network disabled, two CPUs, and a 3 GiB memory limit. It compiled **75 selected source files** and passed **333 tests**. The tests cover original trade-compliance decisions, roster and budget constraints, seeded state transitions, deduplication, multiple game families, error cases, and new offline integration. These tests verify software behavior; they do not evaluate the quality of player ratings or certify legal advice.

## Released scope

`Package.swift` and the Xcode project each select the same 75 files. Those include the original player/value contracts, trade compliance and analyzer, and pure roster, classification, compare, bracket, grid, guess, quiz, survivor, connection, historical-pool, and creator engines. The new SwiftUI front end exposes the flows listed above; it does not imply that every original application screen or every engine has a corresponding released UI.

The broader original Swift source remains in `NBATradeMachine` with its retained development history. Files not selected by the explicit targets are available for inspection and are not compiled into this offline executable. The selected Player, Team, and LeagueRules models use plain optional local identity fields instead of requiring a cloud SDK. The core algorithms are reused directly.

`OfflineTests` contains 31 selected original pure-engine regression files plus a new integration test file. The original tests were adapted only for the released module name and removal of unnecessary main-actor annotations in portable synchronous tests. All fixtures are hand-specified or deterministically generated.
