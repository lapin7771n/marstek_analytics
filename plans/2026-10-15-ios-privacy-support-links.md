# Privacy and support links in the iOS app

**Goal:** the app links its privacy policy and a support contact, so version 1.0 passes App Review guidelines 5.1.1(i) and 1.5.

**Facts:**
- 5.1.1(i): "All apps must include a link to their privacy policy in the App Store Connect metadata field and within the app in an easily accessible manner." ([Apple](https://developer.apple.com/app-store/review/guidelines/#data-collection-and-storage))
- 1.5: "Make sure your app and its Support URL include an easy way to contact you." (same page)
- Both pages are live on GitHub Pages from the `gh-pages` branch:
  - https://lapin7771n.github.io/marstek_analytics/privacy/
  - https://lapin7771n.github.io/marstek_analytics/support/ (contact: GitHub Issues)

**Design:** a last Form section "About" in `SettingsScreen` with two `Link` rows, "Support" and "Privacy policy". Each row has a trailing `arrow.up.forward.app` icon, like the ALLOW LAN row, and opens Safari.

**Constraints:**
- From `ios/`, `make test` passes.
- Branch `feat/ios-battery-widget`; one commit, no co-author trailer.
- Every new string has Ukrainian.
- No network code changes. The links open Safari; the app sends nothing new to the battery.

The four feature branches also edit `BatteryApp.swift`. This section goes after "If it fails", the last section, so a merge conflict is a few lines at the end of the `Form`.

Time: about 20 minutes, plus 10 for build 3.

---

## Task 1: About section

**Files**
- Modify: `ios/Shared/AppLinks.swift`, `ios/App/BatteryApp.swift`, `ios/Shared/Localizable.xcstrings`
- Test: `ios/Tests/LocalizationTests.swift`, new `ios/Tests/AppLinksTests.swift`

- [x] **1.1 Tests first.** Create `ios/Tests/AppLinksTests.swift`:

```swift
import Foundation
import Testing
@testable import BatteryETA

struct AppLinksTests {
    @Test func linksPointAtTheLivePages() {
        #expect(AppLinks.privacy.absoluteString == "https://lapin7771n.github.io/marstek_analytics/privacy/")
        #expect(AppLinks.support.absoluteString == "https://lapin7771n.github.io/marstek_analytics/support/")
    }
}
```

Append to `theAppShipsUkrainian()` in `LocalizationTests`:

```swift
        #expect(uk.localizedString(forKey: "Privacy policy", value: nil, table: nil) == "Політика конфіденційності")
        #expect(uk.localizedString(forKey: "Support", value: nil, table: nil) == "Підтримка")
```

Run `make test`. Expected: build fails, `AppLinks` has no member `privacy`.

- [x] **1.2 Links.** In `ios/Shared/AppLinks.swift` add below `localNetwork`:

```swift
    static let privacy = URL(string: "https://lapin7771n.github.io/marstek_analytics/privacy/")!
    static let support = URL(string: "https://lapin7771n.github.io/marstek_analytics/support/")!
```

- [x] **1.3 Section.** In `ios/App/BatteryApp.swift`, after the closing brace of `Section("If it fails") { … }` and still inside `Form`:

```swift
                Section("About") {
                    link("Support", AppLinks.support)
                    link("Privacy policy", AppLinks.privacy)
                }
```

Add next to `hint(_:_:)`:

```swift
    private func link(_ title: LocalizedStringKey, _ url: URL) -> some View {
        Link(destination: url) {
            HStack {
                Text(title)
                Spacer(minLength: 8)
                Image(systemName: "arrow.up.forward.app").foregroundStyle(.secondary)
            }
            .contentShape(Rectangle())
        }
        .foregroundStyle(.primary)
    }
```

- [x] **1.4 Strings.** Add three entries to `ios/Shared/Localizable.xcstrings`, same shape as `"If it fails"`:

| Key | uk |
| --- | --- |
| `About` | `Про застосунок` |
| `Support` | `Підтримка` |
| `Privacy policy` | `Політика конфіденційності` |

- [x] **1.5 Gate.** `make test` exits 0; the two new assertions in 1.1 pass.

- [x] **1.6 Simulator check.** iPhone 18 Pro Max sim, English and Ukrainian: the About section shows two rows, and each opens its page in Safari. Use a fake IP such as `10.255.255.1` so no request reaches the battery.

- [x] **1.7 Commit.** `feat: link privacy policy and support from the ios app`

## Task 2: Build 3 and the design

- [x] **2.1 Upload.** From `ios/`: `make upload BUILD=3`.
- [ ] **2.2 Attach (owner OK first).** In App Store Connect, swap build 2 for build 3 on version 1.0. Don't submit.
- [x] **2.3 Design.** Add the About section with both rows to `Main.dc.html` on the Claude Design canvas.
- [ ] **2.4 Kit.** Delete blocker 2 from `docs/app-store-submission.md`.
