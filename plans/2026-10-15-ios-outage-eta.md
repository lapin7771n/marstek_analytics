# Lasts until power returns?

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** a tester in a blackout sets when the grid comes back. The app answers "Lasts until 01:20, 40 min to spare." or "Runs out at 01:57, 2 h 03 min short.", and the medium widget shows "Power back 01:20 · +40m".

**UI spec:** artboard "Lasts until power returns" (`project/Outage.dc.html`) on the Battery ETA canvas, https://claude.ai/artifact/1ZfUnFUKedswkhYC5dc9wL. Read-only; the owner edits it.

**Design:**
- The answer uses the ETA the app already shows: `QuickEstimate.estimate` in `ios/Shared/Estimate.swift`, called from `Face.init` in `ios/Shared/Face.swift`. The battery runs out at `reading.time + hours`. The app compares that moment with the power-back time.
- The power-back time is one absolute `Date` in the App Group (`Store.powerBack`), so the widget reads it too.
- Settings screen, new section "POWER BACK AT" after "Now": a "Grid returns" row with a day chip and a time chip, then a verdict row (tinted icon, `LASTS` or `RUNS OUT 01:57`, one sentence), then the footer "Uses the current load. The answer changes as the load changes."
- Picking a time later than now gives today; an earlier or equal time gives tomorrow. The day chip is a menu: Today (only while that time is still ahead today), Tomorrow, Clear.
- No verdict while charging (the grid is on), once the power-back time has passed, or before the first reading. Idle with no backup load says "Lasts until 01:20." with no spare figure.
- Medium widget: the third line becomes the verdict in green or red. The "Now" card in the app keeps "Updated …", as on the artboard.
- The widget timeline gets one entry at the power-back time, so the line goes back to "Updated …" on time.
- A change reloads only the `eta` widget. The app's 30 s poll keeps the snapshot under the widget's 10 min reuse age, so that reload reuses it.

**Deviations from the artboard, for the owner to decide:**
1. The artboard has no empty state. Plan: with no time set, or after it passes, the "Grid returns" row shows one "Set" chip (next whole hour after now + 1 h) and no verdict row. Clearing is the day menu's "Clear".
2. The artboard's widget line mixes "+40 min" and "−2h03". Plan: the widget's compact format for both, "+40m" and "−2h00" (`formatDuration`, 10-minute steps above an hour). The sentence in the app uses whole minutes, "2 h 03 min".
3. A stale reading (over 30 min old or a fetch error) keeps "Updated 2 h ago" on the widget instead of the verdict, so a tester sees the answer is old. The artboard does not show a stale case.

**Constraints:**
- Three sibling worktrees edit `BatteryApp.swift`, `Store.swift`, `Faces.swift`, `Localizable.xcstrings` and `project.yml` in parallel. Keep those edits to added lines where possible. New logic goes in `ios/Shared/Outage.swift`, new views in `ios/Shared/OutageViews.swift`. `project.yml` needs no change, because `Shared/` is globbed.
- From `ios/`, `make test` exits 0. Every new string has Ukrainian. One commit per task on `claude/ios-outage-eta-d407b2`, Conventional Commits, no co-author trailer, no push.

**Battery safety (owner requirement):** the feature must not add load on the Marstek Open API, so the battery never resets or cuts power.

| Rule | Test |
|------|------|
| 1. The verdict comes only from the stored snapshot and the ETA the app already has. Setting the return time or opening the screen sends no request. | `StoreTests.aPowerBackTimeSendsNoBatteryRequest`: a fresh snapshot, a power-back time, then the widget's refresh path and `Face` give a verdict while `FetchCounter` stays at 0. |
| 2. No new polling and no faster poll. The app sends one `ES.GetStatus` every 30 s while open; widgets keep the shared fetch and its 10 min reuse. Never `Bat.GetStatus`. | `StoreTests.pollingStaysAsItIs`: `Refresher.appPollInterval == .seconds(30)` and `Refresher.widgetMaxAge == 600`. `ClientTests.aReadingAsksOnlyForEsStatus` already covers `Bat.GetStatus`. |
| 3. A phase 2 schedule feed talks only to the schedule service on the internet (YASNO, DTEK, or a mirror the owner approves), never to the battery. | Phase 2 adds its own test: a schedule fetch runs with the battery fetch replaced by `FetchCounter`, which stays at 0, and the feed's host is not the battery's IP. |
| 4. Computing the verdict sends zero battery requests. | Covered by the rule 1 test, which uses the existing `FetchCounter` from `StoreTests.swift`. |

**Review focus:**
1. A time earlier than now lands on tomorrow, never on a past moment; "Today" never moves the time into the past. (Task 1 tests.)
2. The verdict counts from the reading's time, not from now, so a 20-minute-old reading does not add 20 minutes of spare. (Task 1 test.)
3. Charging or past the power-back time shows nothing, never "0 min short". (Task 1 tests.)
4. The widget line falls back to "Updated …" when the reading is stale. (Task 2, by reading the view code.)

**Batches:** Tasks 1 and 2 go to one `implementer`, then one `reviewer` on the whole diff.

Time: about 1½ hours, plus 10 minutes to check the screen in the simulator.

---

## Task 1: Verdict model, stored power-back time, face

**Files**
- Create: `ios/Shared/Outage.swift`, `ios/Tests/OutageTests.swift`
- Modify: `ios/Shared/Store.swift`, `ios/Shared/Face.swift`, `ios/App/BatteryApp.swift` (one line in `poll()`)
- Test: `ios/Tests/StoreTests.swift`, `ios/Tests/FaceTests.swift`

- [x] **1.1 Tests first.** Create `ios/Tests/OutageTests.swift`. `reading(...)` lives in `EstimateTests.swift`; its time is `1_760_000_000`, and `reading(acW: 400)` at a 12 % reserve lasts 8.0427 h.

```swift
import Foundation
import Testing
@testable import BatteryETA

struct OutageTests {
    private let readAt = Date(timeIntervalSince1970: 1_760_000_000)

    private func hours(_ h: Double) -> Date { readAt.addingTimeInterval(h * 3600) }

    @Test func lastsWithSpare() throws {
        let verdict = Outage.verdict(reading(acW: 400), floorPct: 12, powerBack: hours(6), now: readAt)
        guard case let .lasts(until, spare) = verdict else { Issue.record("\(String(describing: verdict))"); return }
        #expect(until == hours(6))
        #expect(abs(try #require(spare) - 2.0427) < 0.001)
    }

    @Test func runsOutBeforePowerReturns() {
        let verdict = Outage.verdict(reading(acW: 400), floorPct: 12, powerBack: hours(10), now: readAt)
        guard case let .short(runsOut, short, _) = verdict else { Issue.record("\(String(describing: verdict))"); return }
        #expect(abs(runsOut.timeIntervalSince(hours(8.0427))) < 5)
        #expect(abs(short - 1.9573) < 0.001)
    }

    @Test func countsFromTheReadingNotFromNow() {
        let verdict = Outage.verdict(reading(acW: 400), floorPct: 12, powerBack: hours(10), now: hours(1))
        guard case let .short(_, short, _) = verdict else { Issue.record("\(String(describing: verdict))"); return }
        #expect(abs(short - 1.9573) < 0.001)
    }

    @Test func nothingOncePowerIsBack() {
        #expect(Outage.verdict(reading(acW: 400), floorPct: 12, powerBack: hours(6), now: hours(6)) == nil)
    }

    @Test func nothingWhileCharging() {
        #expect(Outage.verdict(reading(acW: -500), floorPct: 12, powerBack: hours(6), now: readAt) == nil)
    }

    @Test func idleWithoutLoadLasts() {
        #expect(Outage.verdict(reading(soc: 60, acW: 0), floorPct: 12, powerBack: hours(6), now: readAt) == .lasts(until: hours(6), spareHours: nil))
    }

    @Test(arguments: [(0.0, "0 min"), (40.0 / 60, "40 min"), (2.05, "2 h 03 min"), (10.0, "10 h 00 min")])
    func spansUseWholeMinutes(hours: Double, text: String) {
        #expect(formatSpan(hours) == text)
    }
}

struct PowerBackTests {
    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Kyiv")!
        return calendar
    }()

    private func at(_ text: String) -> Date {
        let format = DateFormatter()
        format.calendar = calendar
        format.timeZone = calendar.timeZone
        format.dateFormat = "yyyy-MM-dd HH:mm"
        return format.date(from: text)!
    }

    @Test(arguments: [("2026-10-15 18:00", "2026-10-15 18:00"), ("2026-10-15 09:30", "2026-10-16 09:30"), ("2026-10-15 14:00", "2026-10-16 14:00")])
    func aPickedTimeIsTodayOrTomorrow(picked: String, expected: String) {
        #expect(Outage.nextTime(at(picked), after: at("2026-10-15 14:00"), calendar: calendar) == at(expected))
    }

    @Test func tomorrowKeepsTheTime() {
        #expect(Outage.moved(at("2026-10-15 18:00"), tomorrow: true, now: at("2026-10-15 14:00"), calendar: calendar) == at("2026-10-16 18:00"))
    }

    @Test func todayOnlyWhileTheTimeIsAhead() {
        let now = at("2026-10-15 14:00")
        #expect(Outage.moved(at("2026-10-16 18:00"), tomorrow: false, now: now, calendar: calendar) == at("2026-10-15 18:00"))
        #expect(Outage.moved(at("2026-10-16 09:00"), tomorrow: false, now: now, calendar: calendar) == at("2026-10-16 09:00"))
    }
}
```

Append to `StoreTests`:

```swift
    @Test func powerBackIsStored() {
        let store = store()
        #expect(store.powerBack == nil)
        let back = Date(timeIntervalSince1970: 1_760_020_000)
        store.powerBack = back
        #expect(store.powerBack == back)
        store.powerBack = nil
        #expect(store.powerBack == nil)
    }

    @Test func aPowerBackTimeSendsNoBatteryRequest() async {
        let store = store()
        let good = reading(acW: 400)
        _ = await Refresher.refresh(store, now: good.time) { _ in good }
        let counter = FetchCounter()
        let now = good.time.addingTimeInterval(60)
        store.powerBack = good.time.addingTimeInterval(6 * 3600)
        let snapshot = await Refresher.refresh(store, now: now, maxAge: Refresher.widgetMaxAge) { await counter.read($0) }
        #expect(Face(snapshot, floorPct: store.settings.floorPct, powerBack: store.powerBack, now: now).outage != nil)
        #expect(await counter.count == 0)
    }

    @Test func pollingStaysAsItIs() {
        #expect(Refresher.appPollInterval == .seconds(30))
        #expect(Refresher.widgetMaxAge == 10 * 60)
    }
```

Add to the `FetchCounter` actor at the bottom of `StoreTests.swift`:

```swift
    func read(_ settings: BatterySettings) -> Reading {
        count += 1
        return reading(acW: 400)
    }
```

Append to `FaceTests`:

```swift
    @Test func aPowerBackTimeAddsAVerdict() {
        let back = readAt.addingTimeInterval(6 * 3600)
        #expect(Face(snap(reading(acW: 400)), floorPct: 12, powerBack: back, now: readAt).outage != nil)
        #expect(Face(snap(reading(acW: 400)), floorPct: 12, now: readAt).outage == nil)
        #expect(Face(snap(nil, .noLink), floorPct: 12, powerBack: back, now: readAt).outage == nil)
    }
```

Run `make test`. Expected: the build fails because `Outage`, `formatSpan`, `Store.powerBack`, `Refresher.appPollInterval` and `Face.outage` do not exist.

- [x] **1.2 Model.** Create `ios/Shared/Outage.swift`:

```swift
import Foundation

enum Outage: Equatable {
    case lasts(until: Date, spareHours: Double?)
    case short(runsOutAt: Date, shortHours: Double, back: Date)

    var lasts: Bool {
        if case .lasts = self { true } else { false }
    }

    var back: Date {
        switch self {
        case let .lasts(until, _): until
        case let .short(_, _, back): back
        }
    }

    static func verdict(_ r: Reading, floorPct: Int, powerBack: Date, now: Date) -> Outage? {
        guard powerBack > now else { return nil }
        let est = QuickEstimate.estimate(r, floorPct: Double(floorPct))
        if est.mode == .charging { return nil }
        guard let hours = est.hours else { return .lasts(until: powerBack, spareHours: nil) }
        let runsOut = r.time.addingTimeInterval(hours * 3600)
        let spare = runsOut.timeIntervalSince(powerBack) / 3600
        return spare >= 0 ? .lasts(until: powerBack, spareHours: spare) : .short(runsOutAt: runsOut, shortHours: -spare, back: powerBack)
    }

    static func nextTime(_ picked: Date, after now: Date, calendar: Calendar = .current) -> Date {
        let time = calendar.dateComponents([.hour, .minute], from: picked)
        return calendar.nextDate(after: now, matching: time, matchingPolicy: .nextTime) ?? picked
    }

    static func moved(_ back: Date, tomorrow: Bool, now: Date, calendar: Calendar = .current) -> Date {
        let time = calendar.dateComponents([.hour, .minute], from: back)
        let day = calendar.startOfDay(for: now).addingTimeInterval(tomorrow ? 86_400 : 0)
        let moved = calendar.date(bySettingHour: time.hour ?? 0, minute: time.minute ?? 0, second: 0, of: day) ?? back
        return moved > now ? moved : back
    }
}

func formatSpan(_ hours: Double) -> String {
    let minutes = max(0, Int((hours * 60).rounded()))
    if minutes < 60 { return String(localized: "\(minutes) min") }
    return String(localized: "\(minutes / 60) h \(String(format: "%02d", minutes % 60)) min")
}
```

`startOfDay + 86_400` is off by an hour on a DST night; `date(bySettingHour:of:)` works on the calendar day, so the result still lands on the right day.

- [x] **1.3 Store.** In `ios/Shared/Store.swift`, add below `var snapshot`:

```swift
    var powerBack: Date? {
        get { load("powerBack") }
        set { save(newValue, "powerBack") }
    }
```

In `Refresher`, add `static let appPollInterval: Duration = .seconds(30)` above `widgetMaxAge`. In `ios/App/BatteryApp.swift` `poll()`, replace `.seconds(30)` with `Refresher.appPollInterval`.

- [x] **1.4 Face.**
  - In `ios/Shared/Face.swift`, add `var outage: Outage?` after `var updated: Date?`.
  - Change the init to `init(_ snapshot: Snapshot?, floorPct: Int, powerBack: Date? = nil, now: Date = .now)`. The default keeps every existing caller compiling.
  - After `updated = r.time`, add:

```swift
        outage = powerBack.flatMap { Outage.verdict(r, floorPct: floorPct, powerBack: $0, now: now) }
```

- [x] **1.5 Gate.** Run `make test`. Expected: exit 0. Then change `r.time` to `now` in `Outage.verdict`, check that `countsFromTheReadingNotFromNow` fails, and restore it.

- [x] **1.6 Commit.** `feat: compute whether the battery lasts until power returns`

---

## Task 2: "Power back at" section and widget line

**Files**
- Create: `ios/Shared/OutageViews.swift`
- Modify: `ios/Shared/Faces.swift`, `ios/App/BatteryApp.swift`, `ios/Widget/BatteryWidgets.swift`, `ios/Shared/Localizable.xcstrings`
- Test: `ios/Tests/LocalizationTests.swift`

- [ ] **2.1 Test first.** In `LocalizationTests.theAppShipsUkrainian`, add:

```swift
        #expect(uk.localizedString(forKey: "Lasts until %@, %@ to spare.", value: nil, table: nil) == "Вистачить до %1$@, запас %2$@.")
        #expect(uk.localizedString(forKey: "%lld h %@ min", value: nil, table: nil) == "%lld год %@ хв")
```

Run `make test`. Expected: both expectations fail.

- [ ] **2.2 Views.** Create `ios/Shared/OutageViews.swift`:

```swift
import SwiftUI

struct OutageRow: View {
    let outage: Outage
    let stale: Bool

    private var color: Color { stale ? Palette.stale : outage.lasts ? Palette.good : Palette.bad }

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: outage.lasts ? "checkmark" : "exclamationmark")
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(color)
                .frame(width: 36, height: 36)
                .background(color.opacity(0.16), in: Circle())
            VStack(alignment: .leading, spacing: 2) {
                code.font(.system(size: 13, weight: .bold, design: .rounded)).tracking(1).foregroundStyle(color)
                sentence.font(.system(size: 15, design: .rounded))
            }
        }
        .padding(.vertical, 5)
    }

    private var code: Text {
        switch outage {
        case .lasts: Text("LASTS")
        case let .short(runsOut, _, _): Text("RUNS OUT \(Text(runsOut, style: .time))")
        }
    }

    private var sentence: Text {
        switch outage {
        case let .lasts(until, spare?): Text("Lasts until \(Text(until, style: .time)), \(formatSpan(spare)) to spare.")
        case let .lasts(until, nil): Text("Lasts until \(Text(until, style: .time)).")
        case let .short(runsOut, short, _): Text("Runs out at \(Text(runsOut, style: .time)), \(formatSpan(short)) short.")
        }
    }
}

struct OutageLine: View {
    let outage: Outage

    var body: some View {
        Group {
            switch outage {
            case let .lasts(_, spare?): Text("Power back \(Text(outage.back, style: .time)) · +\(formatDuration(spare))")
            case .lasts(_, nil): Text("Power back \(Text(outage.back, style: .time))")
            case let .short(_, short, _): Text("Power back \(Text(outage.back, style: .time)) · −\(formatDuration(short))")
            }
        }
        .font(.system(size: 12, weight: .bold, design: .rounded))
        .foregroundStyle(outage.lasts ? Palette.good : Palette.bad)
        .lineLimit(1)
        .minimumScaleFactor(0.8)
    }
}
```

`formatSpan`'s `String(localized:)` with `\(minutes / 60)` and a `String` argument extracts as `%lld h %@ min`; the test in 2.1 uses that key.

- [ ] **2.3 Widget line.** In `ios/Shared/Faces.swift` `MediumFace`, wrap the existing `Group { if let updated … }` so the verdict replaces it only on a fresh reading:

```swift
                if let outage = face.outage, !face.stale {
                    OutageLine(outage: outage)
                } else {
                    Group { … existing Updated / Open the app … }
                        .font(.system(size: 12, design: .rounded))
                        .foregroundStyle(face.stale ? Color(hex: 0xA3A3AD) : Palette.label)
                }
```

- [ ] **2.4 Settings section.** In `ios/App/BatteryApp.swift` `SettingsScreen`:
  - Add `@State private var powerBack = Store().powerBack`.
  - Leave the "Now" card's `Face(snapshot, floorPct:)` calls as they are, so the card keeps "Updated …".
  - Add this section after "Now":

```swift
                Section {
                    LabeledContent("Grid returns") {
                        if let back = powerBack, back > .now {
                            HStack(spacing: 6) {
                                Menu {
                                    Button("Today") { setPowerBack(Outage.moved(back, tomorrow: false, now: .now)) }
                                    Button("Tomorrow") { setPowerBack(Outage.moved(back, tomorrow: true, now: .now)) }
                                    Button("Clear", role: .destructive) { setPowerBack(nil) }
                                } label: {
                                    Text(Calendar.current.isDateInToday(back) ? "Today" : "Tomorrow")
                                        .padding(.horizontal, 11).frame(height: 34)
                                        .background(Color(hex: 0x2C2C2E), in: RoundedRectangle(cornerRadius: 8))
                                }
                                .foregroundStyle(.white)
                                DatePicker("Time", selection: backTime, displayedComponents: .hourAndMinute).labelsHidden()
                            }
                        } else {
                            Button("Set") { setPowerBack(Calendar.current.nextDate(after: .now.addingTimeInterval(3600), matching: DateComponents(minute: 0), matchingPolicy: .nextTime)) }
                        }
                    }
                    if let outage = face.outage {
                        OutageRow(outage: outage, stale: face.stale)
                    }
                } header: {
                    Text("Power back at")
                } footer: {
                    Text("Uses the current load. The answer changes as the load changes.")
                }
```

  - Add the helpers:

```swift
    private var face: Face {
        Face(snapshot, floorPct: settings.floorPct, powerBack: powerBack)
    }

    private var backTime: Binding<Date> {
        Binding(get: { powerBack ?? .now }, set: { setPowerBack(Outage.nextTime($0, after: .now)) })
    }

    private func setPowerBack(_ date: Date?) {
        powerBack = date
        store.powerBack = date
        WidgetCenter.shared.reloadTimelines(ofKind: "eta")
    }
```

  - The 30 s poll replaces `snapshot`, so the section redraws and drops the verdict after the time passes.

- [ ] **2.5 Widget.** In `ios/Widget/BatteryWidgets.swift`:
  - `getSnapshot`: pass `powerBack: store.powerBack` to `Face`.
  - `getTimeline`: read `let powerBack = Store().powerBack` next to `floorPct`, pass `powerBack: powerBack` to every `Face(...)`, and before `completion` add:

```swift
            if let powerBack, powerBack > now {
                entries.append(BatteryEntry(date: powerBack, face: Face(snapshot, floorPct: floorPct, powerBack: powerBack, now: powerBack)))
                entries.sort { $0.date < $1.date }
            }
```

- [ ] **2.6 Ukrainian.** Add to `ios/Shared/Localizable.xcstrings`, each with `"state": "translated"`. Run the `ukrainian-translation-review` skill on the values before committing.

| Key | uk |
|-----|----|
| `Power back at` | `Коли дадуть світло` |
| `Grid returns` | `Світло дадуть` |
| `Today` | `Сьогодні` |
| `Tomorrow` | `Завтра` |
| `Clear` | `Скинути` |
| `Set` | `Вказати` |
| `Time` | `Час` |
| `LASTS` | `ВИСТАЧИТЬ` |
| `RUNS OUT %@` | `СЯДЕ О %@` |
| `Lasts until %@, %@ to spare.` | `Вистачить до %1$@, запас %2$@.` |
| `Lasts until %@.` | `Вистачить до %@.` |
| `Runs out at %@, %@ short.` | `Сяде о %1$@, бракує %2$@.` |
| `Power back %@ · +%@` | `Світло о %1$@ · +%2$@` |
| `Power back %@ · −%@` | `Світло о %1$@ · −%2$@` |
| `Power back %@` | `Світло о %@` |
| `%lld min` | `%lld хв` |
| `%lld h %@ min` | `%lld год %@ хв` |
| `Uses the current load. The answer changes as the load changes.` | `Рахує за поточним навантаженням. Відповідь змінюється разом із ним.` |

- [ ] **2.7 Gate.** Run `make test`. Expected: exit 0.

- [ ] **2.8 Look.** Run the app in the `iPhone 18 Pro` simulator, tap "Set", and screenshot the section in English and Ukrainian. Compare with the artboard. With no battery on the LAN there is no reading and no verdict row, so the owner checks the verdict on a real phone.

- [ ] **2.9 Commit.** `feat: show whether the battery lasts until power returns`

---

## Phase 2: schedule feed from DTEK or YASNO (not approved)

Full findings with sources: `plans/2026-10-15-outage-schedule-sources.md`.

**Facts (checked 2026-10-15):**
- Neither DTEK nor YASNO publishes an official API.
- YASNO's own web app uses a public JSON API with no login: `https://app.yasno.ua/api/blackout-service/public/shutdowns/regions/{region}/dsos/{dso}/planned-outages`. It returns each group ("1.1", "1.2" …) with `today` and `tomorrow`, each with a `status` and `slots` of `{start, end, type}` in minutes from midnight. It covers Kyiv city (25/902) and Dnipro (3/301, 3/303). Public address routes turn a street and house into a group. Today every Kyiv group is `EmergencyShutdowns` with empty slots, so the populated slot shape is unconfirmed.
- DTEK sites sit behind Incapsula. Kyiv city and Kyiv oblast challenge plain clients, so an iPhone cannot read them. Dnipro and Odesa embed the schedule in the page and need a CSRF token.
- `Baskerville42/outage-data-ua` (MIT, updated every few minutes) republishes DTEK schedules for Kyiv, Kyiv oblast, Dnipro and Odesa as raw GitHub JSON.
- No terms of use for either site were found.

**Design (owner decisions 15.10: testers live in Kyiv; most reliable source; fill or suggest is our pick):**
- Source: the YASNO API only, Kyiv city (region 25, DSO 902). It is the provider's own feed. The GitHub mirror scrapes DTEK pages through Playwright in CI and adds a second point of failure. DTEK Kyiv blocks plain clients.
- Address from location: on "Use my location" the app asks for When-In-Use location once, reverse-geocodes it with `CLGeocoder`, and turns street and house into a group through `addresses/v2/streets?regionId=25&dsoId=902&query=…`, then `houses`, then `group`. Checked 15.10: `query=Хрещ` returns `вул. Хрещатик` (id 1013), and street 1013 house 42064 returns `{"group":19,"subgroup":1}`. The app stores only the group and the street and house text it shows; it does not keep coordinates. If the street does not match, the tester picks from the returned list.
- Fill: while the app is open it reads `planned-outages` at most every 30 min. When the tester has no manual time, the end of the current or next outage slot for the group fills the power-back time, marked "from YASNO". A manual time wins until it passes. Widgets do not fetch the schedule.
- During `EmergencyShutdowns` (all Kyiv groups on 15.10) there is no slot end, so the section says so and the tester types the time.
- Open check before coding: the group key format in `planned-outages` ("19.1" for group 19, subgroup 1) is unconfirmed, and so is the shape of a populated slot. Both need one day with a published schedule.
- `project.yml` gets `NSLocationWhenInUseUsageDescription`, in English and Ukrainian.

Time: about half a day, plus a day of live use with a populated schedule.
