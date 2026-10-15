# First-launch guide in the iOS app

**Goal:** a new user who opens Battery ETA with no IP saved sees how to turn on the battery's Local API, find its IP, enter it and allow Local Network. They can open the guide again later.

**Facts** (Marstek Android app 2026-10-15, `com.hamedata.marstek`, battery firmware V150):
- Path: device list › tap the battery › gear at the top right › Settings.
- Settings shows **Wi‑Fi** first with `IP: 192.168.68.50` under it. Further down is **Local API** (a switch, "When enabled, the device will also support Open API protocol communication.") and **Ports** `30000`.
- The Marstek app calls the switch "Local API". Our NO LINK hint calls it "Open API".
- The Android package is a cross-platform build (`cross_power_x`), so the iOS Marstek app most likely has the same screens. UNVERIFIED.
- The Marstek app has Ukrainian. There Wi‑Fi is «Налаштування Wi‑Fi», Ports is «Порти», and Local API stays English. The gear screen looks the same in both languages.
- iOS shows the Local Network alert on the first send to the LAN. In this app that is the first "Save and check".
- App Store Review Guideline 5.2.1: "Don't use protected third-party material such as trademarks, copyrighted works, or patented ideas in your app without permission" ([Apple](https://developer.apple.com/app-store/review/guidelines/#intellectual-property)). Screenshots of the Marstek app are Marstek's copyrighted UI, so they may count.
- Crops for option (a), redacted (the device-name suffix `ce8d`, part of the BLE MAC, is blurred): `docs/onboarding/01-gear.png`, `02-ip.png`, `03-local-api.png`. Raw captures stay in `docs/onboarding/raw/`, ignored by git.

**Owner decision: screenshots or diagrams.** The owner chose (a), with Ukrainian screenshots for the Ukrainian app.

| | (a) Cropped Marstek screenshots | (b) Redrawn diagrams |
| --- | --- | --- |
| Review risk | 5.2.1 rejection possible without Marstek's permission | None known: no Marstek pixels or logo |
| Looks like the Marstek app | Exactly | Close: same labels and layout, the app's own colors |
| Dynamic Type, both languages | Fixed images | SwiftUI, scales |
| Marstek app redesign | Screenshots go stale | Labels may go stale |
| Time | about 1 h | about 1.5 h |

**Design:** a sheet "How to connect" with five numbered steps, each a short sentence. Steps 1–3 carry a picture: the screenshot under (a), a SwiftUI diagram under (b).

1. In the Marstek app, open your battery and tap the gear icon at the top right. *(gear picture)*
2. Under Wi‑Fi, write down the IP address. *(IP picture)*
3. Scroll down and turn on Local API. Leave the port at 30000. *(Local API picture)*
4. Enter the IP here and tap Save and check.
5. When the app asks to find devices on your local network, tap Allow.

Below the steps: "This device and the battery must be on the same Wi‑Fi." A "Done" button closes the sheet.

- **When it shows:** at launch while the saved host is empty. No new stored flag: a user who closes it without saving sees it again next launch, which they still need.
- **Open it again:** a `questionmark.circle` toolbar button, labelled "How to connect", on the settings screen.
- **Diagrams (b):** dark cards in the Marstek layout drawn with SF Symbols (`gearshape`, `wifi`, a green switch capsule). Labels copied from the Marstek app use `Text(verbatim:)` and stay English. The control to tap gets a `Palette.good` ring. Diagrams are `accessibilityHidden`; the step text says the same. The IP in the diagram is `192.168.1.50`, the field's placeholder.
- **NO LINK hint:** "Open API" becomes "Local API", the name the Marstek app shows.
- **Find battery** (branch `claude/ios-battery-discovery-91b6ae`): it needs Local API on too, so steps 1 and 3 stay. Once both branches are merged, steps 2 and 4 become one: "Tap Find battery. If it finds nothing, read the IP under Wi‑Fi in the Marstek app." That edit is a follow-up after both merges, not part of this plan.

**Constraints:**
- No network code changes. The guide sends nothing to the battery.
- `BatteryApp.swift` changes stay at the end of `SettingsScreen.body` (one `@State`, a `.toolbar` and a `.sheet`), so merges with the four sibling branches stay small. The guide lives in a new file.
- Every new string has Ukrainian; `LocalizationTests` checks it.
- From `ios/`, `make test` exits 0.
- Branch `claude/ios-first-launch-guide-1374d7`; Conventional Commits, no co-author trailer, no push.

---

## Task 1: Guide sheet

**Files**
- Create: `ios/App/GuideSheet.swift`, `ios/Tests/GuideTests.swift`
- Modify: `ios/App/BatteryApp.swift`, `ios/Shared/Localizable.xcstrings`, `ios/Tests/LocalizationTests.swift`, `.gitignore`
- (a) only: `ios/App/Assets.xcassets/GuideGear.imageset`, `GuideIP.imageset`, `GuideLocalAPI.imageset` (PNG + `Contents.json`)

- [x] **1.1 Tests first.** Create `ios/Tests/GuideTests.swift`:

```swift
import Testing
import UIKit
@testable import BatteryETA

struct GuideTests {
    @Test func showsWhileNoIPIsSaved() {
        #expect(GuideSheet.showsAtLaunch(BatterySettings()))
        #expect(!GuideSheet.showsAtLaunch(BatterySettings(host: "192.168.1.50")))
    }
}
```

(a) only, in the same struct:

```swift
    @Test func theScreenshotsShip() {
        for name in ["GuideGear", "GuideIP", "GuideLocalAPI"] {
            #expect(UIImage(named: name) != nil, "No image \(name)")
        }
    }
```

In `LocalizationTests.everyStringHasUkrainian()` change `>= 38` to `>= 49`. Append to `theAppShipsUkrainian()`:

```swift
        #expect(uk.localizedString(forKey: "How to connect", value: nil, table: nil) == "Як підключити")
        #expect(uk.localizedString(forKey: "Done", value: nil, table: nil) == "Готово")
```

Run `make test`. Expected: build fails, no `GuideSheet`.

- [x] **1.2 Sheet.** Create `ios/App/GuideSheet.swift`:

```swift
import SwiftUI

struct GuideSheet: View {
    static func showsAtLaunch(_ settings: BatterySettings) -> Bool {
        settings.host.isEmpty
    }

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    step(1, "In the Marstek app, open your battery and tap the gear icon at the top right.") { gear }
                    step(2, "Under Wi‑Fi, write down the IP address.") { ip }
                    step(3, "Scroll down and turn on Local API. Leave the port at 30000.") { localAPI }
                    step(4, "Enter the IP here and tap Save and check.") { EmptyView() }
                    step(5, "When the app asks to find devices on your local network, tap Allow.") { EmptyView() }
                    Text("This device and the battery must be on the same Wi‑Fi.")
                        .font(.subheadline).foregroundStyle(.secondary)
                }
                .padding(20)
            }
            .navigationTitle("How to connect")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { Button("Done") { dismiss() }.fontWeight(.semibold) }
        }
    }

    private func step<Picture: View>(_ n: Int, _ text: LocalizedStringKey, @ViewBuilder picture: () -> Picture) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text(verbatim: "\(n)")
                .font(.system(size: 15, weight: .bold, design: .rounded))
                .foregroundStyle(Color(hex: 0x08150F))
                .frame(width: 26, height: 26)
                .background(Palette.good, in: Circle())
            VStack(alignment: .leading, spacing: 10) {
                Text(text)
                picture()
            }
        }
    }
}
```

(a): `gear`, `ip` and `localAPI` are `Image("GuideGear")` etc., `.resizable().scaledToFit()`, clipped to `RoundedRectangle(cornerRadius: 12)`, `accessibilityHidden(true)`. Copy the three crops into the image sets as single-scale PNGs. `GuideIP` and `GuideLocalAPI` are localizable and carry a `uk` variant (`02-ip-uk.png`, `03-local-api-uk.png`).

(b): each is a `private var` that draws the Marstek row, for example:

```swift
    private var localAPI: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: "wifi")
                Text(verbatim: "Local API")
                Spacer()
                Capsule().fill(Color(hex: 0x1FC0D6)).frame(width: 46, height: 28)
                    .overlay(alignment: .trailing) { Circle().fill(.white).padding(3) }
                    .padding(4).overlay(Capsule().stroke(Palette.good, lineWidth: 2))
            }
            HStack {
                Text(verbatim: "Ports")
                Spacer()
                Text(verbatim: "30000").foregroundStyle(.secondary)
                Image(systemName: "chevron.right").foregroundStyle(.secondary)
            }
        }
        .modifier(MockCard())
    }
```

`MockCard` pads 14 pt, fills `Color(hex: 0x1C1C1E)` in a 14 pt rounded rectangle and sets `accessibilityHidden(true)`. `gear` is a header row: `chevron.left`, `Text(verbatim: "Venus E")`, `Spacer`, `gearshape` in a circle with the green ring. `ip` is a `wifi` + `Wi‑Fi` + `chevron.right` row over `IP: 192.168.1.50`, the IP ringed.

- [x] **1.3 Wire it in.** In `ios/App/BatteryApp.swift`, add to `SettingsScreen`:

```swift
    @State private var guide = GuideSheet.showsAtLaunch(Store().settings)
```

and after `.navigationTitle("Battery ETA")`:

```swift
            .toolbar {
                Button { guide = true } label: { Image(systemName: "questionmark.circle") }
                    .accessibilityLabel("How to connect")
            }
            .sheet(isPresented: $guide) { GuideSheet() }
```

- [x] **1.4 NO LINK hint.** In `BatteryApp.swift` change "Open API" to "Local API" in the NO LINK hint, and rename its key in `Localizable.xcstrings`.

- [x] **1.5 Strings.** Add to `ios/Shared/Localizable.xcstrings`, same shape as `"If it fails"`:

| Key | uk |
| --- | --- |
| `How to connect` | `Як підключити` |
| `Done` | `Готово` |
| `In the Marstek app, open your battery and tap the gear icon at the top right.` | `У застосунку Marstek відкрийте свою батарею й торкніться значка шестерні вгорі праворуч.` |
| `Under Wi‑Fi, write down the IP address.` | `Запишіть IP-адресу під «Налаштування Wi‑Fi».` |
| `Scroll down and turn on Local API. Leave the port at 30000.` | `Прокрутіть униз і ввімкніть Local API. Порт залиште 30000.` |
| `Enter the IP here and tap Save and check.` | `Введіть IP тут і торкніться «Зберегти й перевірити».` |
| `When the app asks to find devices on your local network, tap Allow.` | `Коли застосунок попросить доступ до пристроїв у локальній мережі, торкніться «Дозволити».` |
| `This device and the battery must be on the same Wi‑Fi.` | `Цей пристрій і батарея мають бути в одній мережі Wi‑Fi.` |
| `Join the battery's Wi‑Fi, and turn on Local API for the battery in the Marstek app.` (replaces the Open API key) | `Підключіться до Wi‑Fi батареї й увімкніть Local API для батареї в застосунку Marstek.` |

Wi‑Fi keys use U+2011 like the existing ones.

- [x] **1.6 Gitignore.** Ignore `docs/onboarding/`; the crops ship from the asset catalog.

- [x] **1.7 Gate.** From `ios/`: `make test` exits 0.

- [ ] **1.8 Simulator check.** iPhone 18 Pro Max, fresh install, English, then Ukrainian (`-AppleLanguages "(uk)"`): the guide opens at launch; Done closes it; the ? button opens it again; text fits at the largest Dynamic Type size. Save `10.255.255.1` so no request reaches the battery: the guide does not open on the next launch.

- [ ] **1.9 Commit.** `feat: show a first-launch guide in the ios app`

## Task 2: Design

- [ ] **2.1 Artboard.** Read the latest [Battery ETA canvas](https://claude.ai/artifact/1ZfUnFUKedswkhYC5dc9wL), add a "First launch" artboard (`FirstLaunch.dc.html`) with the sheet as built, and publish only that file plus `canvas.json`.
