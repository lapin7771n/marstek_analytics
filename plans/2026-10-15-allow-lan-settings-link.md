# ALLOW LAN opens Settings

**Goal:** when the app or a widget shows `ALLOW LAN`, one tap lands on the page with the Local Network switch.

**Facts:**
- iOS has no public link to Privacy & Security › Local Network. Apple supports only `UIApplication.openSettingsURLString`, which opens the app's own page in Settings ([Apple](https://developer.apple.com/documentation/uikit/uiapplication/opensettingsurlstring), [DTS on the forums](https://developer.apple.com/forums/thread/105986)). `prefs:root=` and `App-Prefs:` links get apps rejected under guideline 2.5.1.
- After an app asks for local network access, its own Settings page shows a Local Network switch. A forum reply says so but no Apple page does, so step 1.5 checks it on the iPad.
- A widget tap can only open the containing app (`widgetURL`). The app then opens Settings.

**Design:**
- The `ALLOW LAN` row under "If it fails" becomes a button that opens the app's Settings page.
- The "Now" card opens the same page when it shows `ALLOW LAN`.
- All three widgets set `widgetURL(batteryeta://local-network)` only while blocked. The app answers that link by opening Settings.
- The hint text keeps the Privacy path as a fallback in case the switch is not on the app's page.

**Constraints:** from `ios/`, `make test` passes. Branch `feat/ios-battery-widget`. One commit, no co-author trailer. Every new string has Ukrainian.

Time: about 30 minutes, plus 5 minutes on the iPad.

---

## Task 1: Settings link for ALLOW LAN

**Files**
- Create: `ios/Shared/AppLinks.swift`
- Modify: `ios/Shared/Face.swift`, `ios/App/BatteryApp.swift`, `ios/Widget/BatteryWidgets.swift`, `ios/project.yml`, `ios/Shared/Localizable.xcstrings`
- Test: `ios/Tests/FaceTests.swift`

- [x] **1.1 Test first.** Append to `FaceTests` (it has `snap(_:_:)` and the `reading(...)` helper):

```swift
    @Test func onlyADeniedPermissionLinksToSettings() {
        #expect(Face(snap(nil, .blocked), floorPct: 12).blocked)
        #expect(Face(snap(reading(acW: 400), .blocked), floorPct: 12).blocked)
        #expect(!Face(snap(reading(acW: 400), .noLink), floorPct: 12).blocked)
        #expect(!Face(snap(reading(acW: 400)), floorPct: 12).blocked)
    }
```

Run `make test`. Expected: the build fails because `Face` has no `blocked`.

- [x] **1.2 Face and link.**
  - In `ios/Shared/Face.swift`, add `var blocked = false` after `var problem: String?`.
  - In `init(_:floorPct:)`, add `blocked = snapshot?.error == .blocked` right after `problem = snapshot?.error?.text`.
  - Create `ios/Shared/AppLinks.swift`:

```swift
import Foundation

enum AppLinks {
    static let localNetwork = URL(string: "batteryeta://local-network")!
}
```

  - In `ios/project.yml`, add the following under `BatteryETA.info.properties`:

```yaml
        CFBundleURLTypes:
          - CFBundleURLName: com.mlapin.marstek.battery
            CFBundleURLSchemes: [batteryeta]
```

- [x] **1.3 App.** In `ios/App/BatteryApp.swift` `SettingsScreen`:
  - Add `@Environment(\.openURL) private var openURL`.
  - Add the helper below:

```swift
    private func openSettings() {
        openURL(URL(string: UIApplication.openSettingsURLString)!)
    }
```

  - On the "Now" card, after `.listRowBackground(Color.clear)`, add `.onTapGesture { if Face(snapshot, floorPct: settings.floorPct).blocked { openSettings() } }`.
  - Replace the `ALLOW LAN` hint line with:

```swift
                    Button(action: openSettings) {
                        HStack {
                            hint("ALLOW LAN", "Tap to open Settings and turn on Local Network. If it is not there: Privacy & Security › Local Network.")
                            Spacer(minLength: 8)
                            Image(systemName: "arrow.up.forward.app").foregroundStyle(.secondary)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
```

  - After `.task { await poll() }`, add `.onOpenURL { url in if url == AppLinks.localNetwork { openSettings() } }`.

- [x] **1.4 Widgets and strings.**
  - In `ios/Widget/BatteryWidgets.swift`, add `.widgetURL(entry.face.blocked ? AppLinks.localNetwork : nil)` after `.containerBackground(...)` in all three configurations (`RingWidget`, `EtaWidget`, `LockWidget`).
  - In `ios/Shared/Localizable.xcstrings`, delete the key `"Settings › Privacy & Security › Local Network › turn on Battery ETA."` and add:

```json
    "Tap to open Settings and turn on Local Network. If it is not there: Privacy & Security › Local Network.": {
      "localizations": {
        "uk": {
          "stringUnit": {
            "state": "translated",
            "value": "Торкніться, щоб відкрити Параметри, і ввімкніть «Локальна мережа». Якщо його там немає: Приватність і безпека › Локальна мережа."
          }
        }
      }
    },
```

Run `make test`. Expected: exit 0.

- [x] **1.5 Commit, then check on the iPad.**
  1. Commit: `git add ios && git commit -m "feat: open settings from allow lan"`.
  2. Install the app on the iPad.
  3. Owner: Settings › Privacy & Security › Local Network › turn off Battery ETA.
  4. Owner: open the app and tap the `ALLOW LAN` row. Pass: Settings opens on Battery ETA's page and shows a Local Network switch. If the switch is not there, the fallback path in the hint is the only route, and the row text stays as written.
  5. Owner: tap a widget that shows `ALLOW LAN`. Pass: the app opens, then Settings opens.
  6. Owner: turn Local Network back on.
