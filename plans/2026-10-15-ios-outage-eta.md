# Lasts until power returns?

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** a tester in a blackout sets when the grid comes back. The app answers "Lasts until 01:20, 40 min to spare." or "Runs out at 01:57, 2 h 03 min short.", and the medium widget shows "Power back 01:20 · +40m".

**UI spec:** artboard "Lasts until power returns" (`project/Outage.dc.html`) on the Battery ETA canvas, https://claude.ai/artifact/1ZfUnFUKedswkhYC5dc9wL. Read-only; the owner edits it.

**Design:**
- The answer uses the ETA the app already shows: `QuickEstimate.estimate` in `ios/Shared/Estimate.swift`, called from `Face.init` in `ios/Shared/Face.swift`. The battery runs out at `reading.time + hours`. The app compares that moment with the power-back time.
- The power-back time is one absolute `Date` in the App Group (`Store.powerBack`), so the widget reads it too.
- Settings screen, new section "POWER BACK AT" after "Now": a "Grid returns" row with a day chip and a time chip, then a verdict row (tinted icon, `LASTS` or `RUNS OUT 01:57`, one sentence), then the footer "Uses the current load. The answer changes as the load changes."
- Picking a time keeps the chosen day while that moment is still ahead (`Outage.retimed`); otherwise a time later than now gives today and an earlier or equal one gives tomorrow. The day chip is a menu: Today (only while that time is still ahead today), Tomorrow, Clear. Days move by calendar day, so the 25-hour DST night still lands on the next day.
- A runs-out moment under a minute before power-back counts as lasting, so the app never says "0 min short".
- No verdict while charging (the grid is on), once the power-back time has passed, or before the first reading. Idle with no backup load says "Lasts until 01:20." with no spare figure.
- Medium widget: the third line becomes the verdict in green or red. The "Now" card in the app keeps "Updated …", as on the artboard.
- The widget timeline gets one entry at the power-back time, so the line goes back to "Updated …" on time.
- A change reloads only the `eta` widget. The app's 30 s poll keeps the snapshot under the widget's 10 min reuse age, so that reload reuses it. While the app's own refresh is in flight, the reload waits until it ends, so the widget never sends a second `ES.GetStatus` beside it.

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
| 3. The phase 2 schedule feed talks only to YASNO (`app.yasno.ua`), never to the battery. | `StoreTests.theScheduleFeedNeverTouchesTheBattery` (Phase 2, Task 4). |
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
        let day = calendar.date(byAdding: .day, value: tomorrow ? 1 : 0, to: calendar.startOfDay(for: now)) ?? now
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

- [x] **2.1 Test first.** In `LocalizationTests.theAppShipsUkrainian`, add:

```swift
        #expect(uk.localizedString(forKey: "Lasts until %@, %@ to spare.", value: nil, table: nil) == "Вистачить до %1$@, запас %2$@.")
        #expect(uk.localizedString(forKey: "%lld h %@ min", value: nil, table: nil) == "%lld год %@ хв")
```

Run `make test`. Expected: both expectations fail.

- [x] **2.2 Views.** Create `ios/Shared/OutageViews.swift`:

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

- [x] **2.3 Widget line.** In `ios/Shared/Faces.swift` `MediumFace`, wrap the existing `Group { if let updated … }` so the verdict replaces it only on a fresh reading:

```swift
                if let outage = face.outage, !face.stale {
                    OutageLine(outage: outage)
                } else {
                    Group { … existing Updated / Open the app … }
                        .font(.system(size: 12, design: .rounded))
                        .foregroundStyle(face.stale ? Color(hex: 0xA3A3AD) : Palette.label)
                }
```

- [x] **2.4 Settings section.** In `ios/App/BatteryApp.swift` `SettingsScreen`:
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

- [x] **2.5 Widget.** In `ios/Widget/BatteryWidgets.swift`:
  - `getSnapshot`: pass `powerBack: store.powerBack` to `Face`.
  - `getTimeline`: read `let powerBack = Store().powerBack` next to `floorPct`, pass `powerBack: powerBack` to every `Face(...)`, and before `completion` add:

```swift
            if let powerBack, powerBack > now {
                entries.append(BatteryEntry(date: powerBack, face: Face(snapshot, floorPct: floorPct, powerBack: powerBack, now: powerBack)))
                entries.sort { $0.date < $1.date }
            }
```

- [x] **2.6 Ukrainian.** Add to `ios/Shared/Localizable.xcstrings`, each with `"state": "translated"`. Run the `ukrainian-translation-review` skill on the values before committing.

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
| `Uses the current load. The answer changes as the load changes.` | `Розраховано за поточним навантаженням. Якщо воно зміниться, зміниться й відповідь.` |

- [x] **2.7 Gate.** Run `make test`. Expected: exit 0.

- [x] **2.8 Look.** Run the app in the `iPhone 18 Pro` simulator, tap "Set", and screenshot the section in English and Ukrainian. Compare with the artboard. With no battery on the LAN there is no reading and no verdict row, so the owner checks the verdict on a real phone.

- [x] **2.9 Commit.** `feat: show whether the battery lasts until power returns`

---

## Phase 2: fill the power-back time from the YASNO schedule

Full findings with sources: `plans/2026-10-15-outage-schedule-sources.md`.

**Facts (checked 2026-10-15):**
- Neither DTEK nor YASNO publishes an official API. DTEK Kyiv blocks plain clients (Incapsula).
- YASNO's own web app reads a public JSON API with no login: `https://app.yasno.ua/api/blackout-service/public/shutdowns/regions/25/dsos/902/planned-outages` for Kyiv city.
- The feed is an object keyed by group. The web app builds the key as `"\(group).\(subgroup)"`, or `"\(group)"` when the subgroup is 0. On 15.10 Kyiv had 60 keys, `"1.1"` to `"60.1"`.
- Each key has `today` and `tomorrow`. Each day has `date` (local midnight with offset, `"2026-10-15T00:00:00+03:00"`), `status` and `slots`. A populated day covers 0 to 1440 with no gaps, for example group 19.1 on 15.10: `{0,480,NotPlanned}`, `{480,690,Definite}`, `{690,1440,NotPlanned}`. Two outages in a day are two separate `Definite` slots.
- Slot types in the web app: `Definite`, `Possible`, `NotPlanned`, `Unknown`. Day statuses: `ScheduleApplies`, `EmergencyShutdowns`, `WaitingForSchedule`, `NoOutages`. A `WaitingForSchedule` day still carries one `NotPlanned` slot over the whole day.
- Address routes: `addresses/v2/streets?regionId=25&dsoId=902&query=Хрещ` returns `[{id:599,value:"вул. Набережно-Хрещатицька"},{id:1013,value:"вул. Хрещатик"}]`; `houses?…&streetId=1013&query=1` returns `{id,value}` pairs; `group?…&streetId=1013&houseId=42494` returns `{"group":19,"subgroup":1}`. The web app also accepts a bare number or string as the group reply.
- House ids change: house 1 on Khreshchatyk was 42064 earlier on 15.10 and 42494 later. Store the group, never the ids.

**Design (owner decisions 15.10):**
- Source: YASNO only, Kyiv city (region 25, DSO 902).
- Address: an "Address" screen. "Use my location" asks for When-In-Use location once, reverse-geocodes it with `CLGeocoder` in Ukrainian, and searches YASNO streets with the street name minus its type word ("вулиця Хрещатик" → "Хрещатик"). One exact match picks itself; otherwise the tester taps the street in the list. The house works the same way. Typing the street works without location. The app stores only the group and the address text, never coordinates.
- Feed: while the app is open it reads `planned-outages` at most every 30 min, and at once when the group changes. The last read stays in the App Group, so reopening the app inside 30 min reads nothing.
- Power-back time from the schedule: the end of the current or next `Definite` span. Touching slots merge, so 21:00–24:00 today plus 00:00–02:00 tomorrow ends at 02:00. Only `ScheduleApplies` days count. `EmergencyShutdowns` today gives no time. `Possible` slots do not count. Minutes are wall-clock time in Europe/Kyiv.
- Fill: every 30 s tick the app recomputes the answer from the stored read, with no network. A manual time still ahead wins. Otherwise the slot end fills the power-back time, marked as from YASNO. A YASNO time is dropped when the schedule no longer has a slot ahead. Any manual edit (time, day, Clear) makes the time manual.
- Widgets do not fetch the schedule. They show whatever power-back time the App Group holds.
- The feed lives in `ios/App/`, so the widget target cannot call it. It has no access to `MarstekClient` or `Refresher`.

**Deviations, for the owner to decide:**
1. Before an outage starts, the next slot's end fills the time, and the verdict counts down from the current load. With the grid still on, that answer is cautious: it assumes the battery drains from now.
2. A YASNO time has no "Clear" in the day menu, because the next 30 s tick would fill it again. To stop using YASNO, the tester removes the address. A manual time gets a "Use YASNO" item when YASNO has a slot ahead.
3. After a YASNO time passes with the app closed, the widget shows "Updated …" until the app opens and fills the next slot.

**Battery safety, rule 3 test:** `StoreTests.theScheduleFeedNeverTouchesTheBattery`. A schedule tick fills the power-back time from a fake YASNO reply. Then the widget refresh path runs with the battery fetch replaced by `FetchCounter`, which stays at 0. Every URL the feed asked for has host `app.yasno.ua`, and none has the battery's host.

**Review focus:**
1. The feed cannot reach the battery: no `MarstekClient`, `Refresher.refresh` or `BatteryLine` call in `ios/App/Yasno.swift` or `AddressScreen.swift`. (Task 4 test, and by reading.)
2. A manual time ahead is never overwritten by the schedule. (Task 3 test.)
3. The feed reads at most once per 30 min per group. (Task 4 test.)
4. Slot times use Europe/Kyiv, not the phone's time zone. (Task 3 tests run in Kyiv time; read `Schedule.time`.)
5. No coordinates are stored or sent. Only street and house text goes to YASNO. (By reading Task 5.)

**Batches:** Tasks 3 and 4 go to one `implementer`, then Tasks 5 and 6 to a second one. One `reviewer` on the whole phase 2 diff, then one `fixer`.

Time: about 4 hours, plus 20 minutes in the simulator. A day of live use on a phone with a published schedule is the owner's.

---

## Task 3: Schedule model and fill rule

**Files**
- Create: `ios/Shared/Schedule.swift`, `ios/Tests/ScheduleTests.swift`
- Modify: `ios/Shared/Store.swift` (added lines only)

- [x] **3.1 Tests first.** Create `ios/Tests/ScheduleTests.swift`:

```swift
import Foundation
import Testing
@testable import BatteryETA

let yasnoSample = """
{"19.1":{"today":{"slots":[{"start":0,"end":480,"type":"NotPlanned"},{"start":480,"end":690,"type":"Definite"},{"start":690,"end":1440,"type":"NotPlanned"}],"date":"2026-10-15T00:00:00+03:00","status":"ScheduleApplies"},"tomorrow":{"slots":[{"start":0,"end":1440,"type":"NotPlanned"}],"date":"2026-10-16T00:00:00+03:00","status":"WaitingForSchedule"},"updatedOn":"2026-10-15T02:24:56+00:00"}}
"""

func kyiv(_ text: String) -> Date {
    let format = DateFormatter()
    format.calendar = Schedule.kyiv
    format.timeZone = Schedule.kyiv.timeZone
    format.dateFormat = "yyyy-MM-dd HH:mm"
    return format.date(from: text)!
}

struct ScheduleTests {
    private func day(_ ymd: String, _ status: String = "ScheduleApplies", off: [(Int, Int)] = [], type: String = "Definite") -> ScheduleDay {
        ScheduleDay(date: kyiv("\(ymd) 00:00"), status: status, slots: off.map { ScheduleSlot(start: $0.0, end: $0.1, type: type) })
    }

    private func days(today: ScheduleDay, tomorrow: ScheduleDay? = nil) -> GroupDays {
        GroupDays(today: today, tomorrow: tomorrow ?? day("2026-10-16", "WaitingForSchedule"))
    }

    @Test func decodesTheLiveFeed() throws {
        let days = try #require(try Schedule.decode(Data(yasnoSample.utf8), key: "19.1"))
        #expect(days.today.status == "ScheduleApplies")
        #expect(days.today.slots[1] == ScheduleSlot(start: 480, end: 690, type: "Definite"))
        #expect(days.today.date == kyiv("2026-10-15 00:00"))
        #expect(try Schedule.decode(Data(yasnoSample.utf8), key: "19") == nil)
    }

    @Test func groupKeysMatchTheFeed() {
        #expect(OutageGroup(group: 19, subgroup: 1, address: "").key == "19.1")
        #expect(OutageGroup(group: 5, subgroup: 0, address: "").key == "5")
    }

    @Test(arguments: ["2026-10-15 07:00", "2026-10-15 09:00"])
    func theCurrentOrNextSlotCounts(now: String) {
        let answer = Schedule.answer(days(today: day("2026-10-15", off: [(480, 690), (1020, 1230)])), now: kyiv(now))
        #expect(answer == .off(from: kyiv("2026-10-15 08:00"), until: kyiv("2026-10-15 11:30")))
    }

    @Test func afterTodaysSlotsTomorrowCounts() {
        let answer = Schedule.answer(days(today: day("2026-10-15", off: [(480, 690)]), tomorrow: day("2026-10-16", off: [(840, 1050)])), now: kyiv("2026-10-15 12:00"))
        #expect(answer == .off(from: kyiv("2026-10-16 14:00"), until: kyiv("2026-10-16 17:30")))
    }

    @Test func aSlotAcrossMidnightEndsTomorrow() {
        let answer = Schedule.answer(days(today: day("2026-10-15", off: [(1260, 1440)]), tomorrow: day("2026-10-16", off: [(0, 120)])), now: kyiv("2026-10-15 22:00"))
        #expect(answer == .off(from: kyiv("2026-10-15 21:00"), until: kyiv("2026-10-16 02:00")))
    }

    @Test func anUnpublishedTomorrowDoesNotCount() {
        let answer = Schedule.answer(days(today: day("2026-10-15", off: [(480, 690)]), tomorrow: day("2026-10-16", "WaitingForSchedule", off: [(840, 1050)])), now: kyiv("2026-10-15 12:00"))
        #expect(answer == .clear)
    }

    @Test func emergencyHasNoEnd() {
        #expect(Schedule.answer(days(today: day("2026-10-15", "EmergencyShutdowns")), now: kyiv("2026-10-15 12:00")) == .emergency)
    }

    @Test func possibleSlotsDoNotCount() {
        #expect(Schedule.answer(days(today: day("2026-10-15", off: [(840, 1050)], type: "Possible")), now: kyiv("2026-10-15 12:00")) == .clear)
    }

    @Test func aManualTimeAheadWins() {
        let now = kyiv("2026-10-15 09:00")
        let manual = kyiv("2026-10-15 13:00")
        #expect(Schedule.fill(PowerBack(at: manual, fromSchedule: false), answer: .off(from: now, until: kyiv("2026-10-15 11:30")), now: now) == PowerBack(at: manual, fromSchedule: false))
    }

    @Test func theScheduleFillsAnEmptyOrPassedTime() {
        let now = kyiv("2026-10-15 09:00")
        let filled = PowerBack(at: kyiv("2026-10-15 11:30"), fromSchedule: true)
        let answer = ScheduleAnswer.off(from: now, until: kyiv("2026-10-15 11:30"))
        #expect(Schedule.fill(PowerBack(at: nil, fromSchedule: false), answer: answer, now: now) == filled)
        #expect(Schedule.fill(PowerBack(at: kyiv("2026-10-15 08:00"), fromSchedule: false), answer: answer, now: now) == filled)
    }

    @Test(arguments: [ScheduleAnswer.clear, .emergency, nil] as [ScheduleAnswer?])
    func aScheduleTimeGoesWithItsSlot(answer: ScheduleAnswer?) {
        let now = kyiv("2026-10-15 09:00")
        #expect(Schedule.fill(PowerBack(at: kyiv("2026-10-15 11:30"), fromSchedule: true), answer: answer, now: now) == PowerBack(at: nil, fromSchedule: false))
    }

    @Test func noScheduleLeavesAManualTime() {
        let manual = PowerBack(at: kyiv("2026-10-15 08:00"), fromSchedule: false)
        #expect(Schedule.fill(manual, answer: nil, now: kyiv("2026-10-15 09:00")) == manual)
    }
}
```

Append to `StoreTests`:

```swift
    @Test func theOutageGroupAndScheduleAreStored() {
        let store = store()
        #expect(store.outageGroup == nil && store.schedule == nil && !store.powerBackFromSchedule)
        store.outageGroup = OutageGroup(group: 19, subgroup: 1, address: "вул. Хрещатик, 1")
        store.schedule = ScheduleState(key: "19.1", checkedAt: .now, days: nil)
        store.powerBackFromSchedule = true
        #expect(store.outageGroup?.key == "19.1" && store.schedule?.key == "19.1" && store.powerBackFromSchedule)
    }
```

Run `make test`. Expected: the build fails because `Schedule`, `OutageGroup` and the new `Store` properties do not exist.

- [x] **3.2 Model.** Create `ios/Shared/Schedule.swift`:

```swift
import Foundation

struct OutageGroup: Codable, Equatable {
    var group: Int
    var subgroup: Int
    var address: String

    var key: String { subgroup == 0 ? "\(group)" : "\(group).\(subgroup)" }
}

struct ScheduleSlot: Codable, Equatable {
    var start: Int
    var end: Int
    var type: String
}

struct ScheduleDay: Codable, Equatable {
    var date: Date
    var status: String
    var slots: [ScheduleSlot]
}

struct GroupDays: Codable, Equatable {
    var today: ScheduleDay
    var tomorrow: ScheduleDay
}

struct ScheduleState: Codable, Equatable {
    var key: String
    var checkedAt: Date
    var days: GroupDays?
    var failed = false
}

enum ScheduleAnswer: Equatable {
    case off(from: Date, until: Date)
    case emergency
    case clear
}

struct PowerBack: Equatable {
    var at: Date?
    var fromSchedule: Bool
}

enum Schedule {
    static let readEvery: TimeInterval = 30 * 60

    static let kyiv: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Kyiv")!
        return calendar
    }()

    static func decode(_ data: Data, key: String) throws -> GroupDays? {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode([String: GroupDays].self, from: data)[key]
    }

    static func answer(_ days: GroupDays, now: Date, calendar: Calendar = kyiv) -> ScheduleAnswer {
        if days.today.status == "EmergencyShutdowns" { return .emergency }
        var spans: [(from: Date, until: Date)] = []
        for day in [days.today, days.tomorrow] where day.status == "ScheduleApplies" {
            for slot in day.slots where slot.type == "Definite" {
                let from = time(slot.start, on: day.date, calendar), until = time(slot.end, on: day.date, calendar)
                if let last = spans.last, from <= last.until {
                    spans[spans.count - 1].until = max(last.until, until)
                } else {
                    spans.append((from, until))
                }
            }
        }
        guard let next = spans.first(where: { $0.until > now }) else { return .clear }
        return .off(from: next.from, until: next.until)
    }

    static func fill(_ current: PowerBack, answer: ScheduleAnswer?, now: Date) -> PowerBack {
        if let at = current.at, at > now, !current.fromSchedule { return current }
        if case let .off(_, until)? = answer { return PowerBack(at: until, fromSchedule: true) }
        return current.fromSchedule ? PowerBack(at: nil, fromSchedule: false) : current
    }

    private static func time(_ minutes: Int, on day: Date, _ calendar: Calendar) -> Date {
        let midnight = calendar.startOfDay(for: day)
        if minutes >= 1440 { return calendar.date(byAdding: .day, value: 1, to: midnight) ?? midnight }
        return calendar.date(bySettingHour: minutes / 60, minute: minutes % 60, second: 0, of: midnight) ?? midnight
    }
}
```

- [x] **3.3 Store.** In `ios/Shared/Store.swift`, add below `var powerBack`:

```swift
    var powerBackFromSchedule: Bool {
        get { load("powerBackFromSchedule") ?? false }
        set { save(newValue, "powerBackFromSchedule") }
    }

    var outageGroup: OutageGroup? {
        get { load("outageGroup") }
        set { save(newValue, "outageGroup") }
    }

    var schedule: ScheduleState? {
        get { load("schedule") }
        set { save(newValue, "schedule") }
    }
```

- [x] **3.4 Gate.** Run `make test`. Expected: exit 0. Then delete the `!current.fromSchedule` check in `Schedule.fill`, check that `aManualTimeAheadWins` still passes but `aScheduleTimeGoesWithItsSlot` fails, and restore it.

- [x] **3.5 Commit.** `feat: compute the power-back time from a yasno schedule`

---

## Task 4: YASNO client and the 30 min feed

**Files**
- Create: `ios/App/Yasno.swift`
- Modify: `ios/Tests/ScheduleTests.swift`, `ios/Tests/StoreTests.swift`

- [x] **4.1 Tests first.** Append to `ScheduleTests.swift`:

```swift
actor URLLog {
    var urls: [URL] = []
    func add(_ url: URL) { urls.append(url) }
}

struct FeedTests {
    private func store() -> Store {
        let store = Store(defaults: UserDefaults(suiteName: "test.\(UUID().uuidString)"))
        store.settings = BatterySettings(host: "192.168.68.50", port: 30000, floorPct: 12)
        store.outageGroup = OutageGroup(group: 19, subgroup: 1, address: "вул. Хрещатик, 1")
        return store
    }

    private func client(_ log: URLLog, reply: String = yasnoSample) -> YasnoClient {
        YasnoClient { url in
            await log.add(url)
            return Data(reply.utf8)
        }
    }

    @Test func aTickFillsTheSlotEnd() async {
        let store = store()
        let changed = await ScheduleFeed.tick(store, now: kyiv("2026-10-15 09:00"), client: client(URLLog()))
        #expect(changed)
        #expect(store.powerBack == kyiv("2026-10-15 11:30"))
        #expect(store.powerBackFromSchedule)
    }

    @Test func theFeedReadsAtMostEvery30Minutes() async {
        let store = store()
        let log = URLLog()
        let start = kyiv("2026-10-15 07:00")
        for minutes in [0.0, 10, 29, 31] {
            _ = await ScheduleFeed.tick(store, now: start.addingTimeInterval(minutes * 60), client: client(log))
        }
        #expect(await log.urls.count == 2)
        store.outageGroup = OutageGroup(group: 20, subgroup: 1, address: "вул. Хрещатик, 2")
        _ = await ScheduleFeed.tick(store, now: start.addingTimeInterval(32 * 60), client: client(log))
        #expect(await log.urls.count == 3)
    }

    @Test func aFailedReadKeepsTheLastSchedule() async {
        let store = store()
        let start = kyiv("2026-10-15 07:00")
        _ = await ScheduleFeed.tick(store, now: start, client: client(URLLog()))
        let failing = YasnoClient { _ in throw URLError(.notConnectedToInternet) }
        _ = await ScheduleFeed.tick(store, now: start.addingTimeInterval(31 * 60), client: failing)
        #expect(store.schedule?.failed == true)
        #expect(store.schedule?.days != nil)
        #expect(store.powerBack == kyiv("2026-10-15 11:30"))
    }

    @Test func noGroupReadsNothing() async {
        let store = store()
        store.outageGroup = nil
        let log = URLLog()
        let changed = await ScheduleFeed.tick(store, now: kyiv("2026-10-15 09:00"), client: client(log))
        #expect(!changed)
        #expect(await log.urls.isEmpty)
    }

    @Test(arguments: [("вулиця Хрещатик", "Хрещатик"), ("проспект Перемоги", "Перемоги"), ("бульвар Лесі Українки", "Лесі Українки"), ("Хрещатик", "Хрещатик")])
    func aStreetIsSearchedWithoutItsType(street: String, query: String) {
        #expect(Address.query(street) == query)
    }

    @Test func aStreetMatchesItsYasnoName() {
        let streets = [YasnoChoice(id: 599, value: "вул. Набережно-Хрещатицька"), YasnoChoice(id: 1013, value: "вул. Хрещатик")]
        #expect(Address.match("вулиця Хрещатик", in: streets)?.id == 1013)
        #expect(Address.match("Хрещ", in: streets) == nil)
        #expect(Address.match("10А", in: [YasnoChoice(id: 1, value: "10"), YasnoChoice(id: 2, value: "10а")])?.id == 2)
    }

    @Test(arguments: [#"{"group":19,"subgroup":1}"#, "19"])
    func aGroupReplyDecodes(reply: String) async throws {
        let group = try await client(URLLog(), reply: reply).group(street: 1013, house: 42494)
        #expect(group.group == 19)
    }
}
```

Append to `StoreTests` (battery safety rule 3). The reply is built around the reading's own time, so the widget path reuses the stored snapshot:

```swift
    @Test func theScheduleFeedNeverTouchesTheBattery() async throws {
        let store = store()
        let good = reading(acW: 400)
        _ = await Refresher.refresh(store, now: good.time) { _ in good }
        store.outageGroup = OutageGroup(group: 19, subgroup: 1, address: "вул. Хрещатик, 1")
        let midnight = Schedule.kyiv.startOfDay(for: good.time)
        let date = ISO8601DateFormatter.string(from: midnight, timeZone: Schedule.kyiv.timeZone, formatOptions: .withInternetDateTime)
        let reply = #"{"19.1":{"today":{"slots":[{"start":0,"end":1440,"type":"Definite"}],"date":"\#(date)","status":"ScheduleApplies"},"tomorrow":{"slots":[],"date":"\#(date)","status":"WaitingForSchedule"}}}"#
        let log = URLLog()
        let now = good.time.addingTimeInterval(60)
        #expect(await ScheduleFeed.tick(store, now: now, client: YasnoClient { url in await log.add(url); return Data(reply.utf8) }))
        let counter = FetchCounter()
        let snapshot = await Refresher.refresh(store, now: now, maxAge: Refresher.widgetMaxAge) { await counter.read($0) }
        #expect(Face(snapshot, floorPct: 12, powerBack: store.powerBack, now: now).outage != nil)
        #expect(await counter.count == 0)
        let hosts = await log.urls.map(\.host)
        #expect(!hosts.isEmpty && hosts.allSatisfy { $0 == "app.yasno.ua" && $0 != store.settings.host })
    }
```

Run `make test`. Expected: the build fails because `YasnoClient`, `ScheduleFeed`, `Address` and `YasnoChoice` do not exist.

- [x] **4.2 Client and feed.** Create `ios/App/Yasno.swift`:

```swift
import Foundation

struct YasnoChoice: Codable, Hashable, Identifiable {
    var id: Int
    var value: String
}

struct YasnoClient {
    static let base = URL(string: "https://app.yasno.ua/api/blackout-service/public/shutdowns/")!
    static let region = 25
    static let dso = 902

    var get: @Sendable (URL) async throws -> Data = YasnoClient.live

    static func live(_ url: URL) async throws -> Data {
        let (data, response) = try await URLSession.shared.data(for: URLRequest(url: url, timeoutInterval: 15))
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw URLError(.badServerResponse) }
        return data
    }

    func planned(_ key: String) async throws -> GroupDays? {
        try Schedule.decode(await get(Self.base.appending(path: "regions/\(Self.region)/dsos/\(Self.dso)/planned-outages")), key: key)
    }

    func streets(_ query: String) async throws -> [YasnoChoice] {
        try await list("addresses/v2/streets", ["query": query])
    }

    func houses(street: Int, query: String) async throws -> [YasnoChoice] {
        try await list("addresses/v2/houses", ["streetId": "\(street)", "query": query])
    }

    func group(street: Int, house: Int) async throws -> (group: Int, subgroup: Int) {
        let data = try await get(url("addresses/v2/group", ["streetId": "\(street)", "houseId": "\(house)"]))
        struct Reply: Decodable { var group: Int; var subgroup: Int? }
        if let reply = try? JSONDecoder().decode(Reply.self, from: data) { return (reply.group, reply.subgroup ?? 0) }
        let text = String(decoding: data, as: UTF8.self).trimmingCharacters(in: CharacterSet(charactersIn: "\" \n"))
        guard let group = Int(text) else { throw URLError(.cannotParseResponse) }
        return (group, 0)
    }

    private func list(_ path: String, _ query: [String: String]) async throws -> [YasnoChoice] {
        try JSONDecoder().decode([YasnoChoice].self, from: await get(url(path, query)))
    }

    private func url(_ path: String, _ query: [String: String]) -> URL {
        let items = [URLQueryItem(name: "regionId", value: "\(Self.region)"), URLQueryItem(name: "dsoId", value: "\(Self.dso)")]
            + query.sorted { $0.key < $1.key }.map { URLQueryItem(name: $0.key, value: $0.value) }
        return Self.base.appending(path: path).appending(queryItems: items)
    }
}

enum ScheduleFeed {
    static func tick(_ store: Store, now: Date = .now, client: YasnoClient = YasnoClient()) async -> Bool {
        var state = store.schedule
        if let group = store.outageGroup {
            let age = state.map { now.timeIntervalSince($0.checkedAt) } ?? .infinity
            if state?.key != group.key || !(0..<Schedule.readEvery).contains(age) {
                let kept = state?.key == group.key ? state?.days : nil
                do {
                    state = ScheduleState(key: group.key, checkedAt: now, days: try await client.planned(group.key))
                } catch {
                    state = ScheduleState(key: group.key, checkedAt: now, days: kept, failed: true)
                }
                store.schedule = state
            }
        } else {
            state = nil
        }
        let current = PowerBack(at: store.powerBack, fromSchedule: store.powerBackFromSchedule)
        let next = Schedule.fill(current, answer: state?.days.map { Schedule.answer($0, now: now) }, now: now)
        guard next != current else { return false }
        store.powerBack = next.at
        store.powerBackFromSchedule = next.fromSchedule
        return true
    }
}

enum Address {
    private static let types: Set<String> = ["вулиця", "вул.", "проспект", "просп.", "бульвар", "бульв.", "провулок", "пров.", "площа", "пл.", "набережна", "наб.", "узвіз", "шосе", "алея", "проїзд", "тупик", "майдан"]

    static func query(_ street: String) -> String {
        street.split(separator: " ").filter { !types.contains($0.lowercased()) }.joined(separator: " ")
    }

    static func match(_ name: String, in choices: [YasnoChoice]) -> YasnoChoice? {
        let wanted = query(name).lowercased()
        let exact = choices.filter { query($0.value).lowercased() == wanted }
        return exact.count == 1 ? exact[0] : nil
    }
}
```

- [x] **4.3 Gate.** Run `make test`. Expected: exit 0. Then change `Schedule.readEvery` to `60`, check that `theFeedReadsAtMostEvery30Minutes` fails, and restore it.

- [x] **4.4 Live check.** In a scratch Swift script outside the repo, call `YasnoClient.live` on the `planned-outages` URL through `URLSession` and print the status code and the first key. Expected: 200 and a key such as `"1.1"`. This shows Incapsula lets `URLSession` through.

- [x] **4.5 Commit.** `feat: read the yasno schedule every 30 min while the app is open`

---

## Task 5: Address screen with one-time location

**Files**
- Create: `ios/App/AddressScreen.swift`
- Modify: `ios/project.yml`, `ios/App/Info.plist` (regenerated), `ios/App/InfoPlist.xcstrings`

- [x] **5.1 Location string.** In `ios/project.yml` under `BatteryETA.info.properties`, add `NSLocationWhenInUseUsageDescription: Battery ETA finds your street once to look up your outage group.` Run `make project` so `App/Info.plist` picks it up. Add the key to `App/InfoPlist.xcstrings` with uk `Battery ETA один раз визначає вашу вулицю, щоб знайти групу відключень.`

- [x] **5.2 Screen.** Create `ios/App/AddressScreen.swift` with:
  - `LocationOnce`, a `CLLocationManagerDelegate` class with `func locate() async -> CLLocation?`. It asks When-In-Use once when not determined, calls `requestLocation()` once authorized, and returns nil on denial or error. `desiredAccuracy = kCLLocationAccuracyHundredMeters`. It keeps no location after it returns.
  - `AddressScreen(group: OutageGroup?, onSave: (OutageGroup?) -> Void)`, pushed from the "Address" row. State: `street` text, `streets: [YasnoChoice]`, picked `YasnoChoice?`, `house` text, `houses`, a `note: LocalizedStringKey?` and a `busy` flag.
  - Section 1: a "Use my location" button. It runs `LocationOnce().locate()`, then `CLGeocoder().reverseGeocodeLocation(location, preferredLocale: Locale(identifier: "uk_UA")).first`, puts `thoroughfare` into `street` and `subThoroughfare` into `house`. Nil location sets the note "Location is off. Type the street."
  - Section "Street": a text field. `.task(id: street)` waits 400 ms, then loads `YasnoClient().streets(Address.query(street))` when the query has 3 or more letters. `Address.match` picks one exact match by itself; otherwise the results show as tappable rows. No results set the note "No match. YASNO covers Kyiv city only."
  - Section "House", shown once a street is picked: the same pattern with `houses(street:query:)`. Picking a house calls `group(street:house:)`, then `onSave(OutageGroup(group:, subgroup:, address: "\(street.value), \(house.value)"))` and dismisses.
  - When a group is stored, a destructive "Remove address" button calls `onSave(nil)`.
  - Footer: "The app keeps only the group and the address text, not your location."
  - A failed request sets the note "YASNO did not answer."

- [x] **5.3 Gate.** Run `make test`. Expected: exit 0.

- [x] **5.4 Commit.** `feat: find the yasno outage group from the address`

---

## Task 6: Schedule in the "Power back at" section

**Files**
- Create: `ios/App/ScheduleViews.swift`
- Modify: `ios/App/BatteryApp.swift`, `ios/Shared/Localizable.xcstrings`
- Test: `ios/Tests/LocalizationTests.swift`

- [x] **6.1 Test first.** In `LocalizationTests.theAppShipsUkrainian`, add:

```swift
        #expect(uk.localizedString(forKey: "YASNO, group %@: off %@–%@.", value: nil, table: nil) == "YASNO, група %1$@: без світла %2$@–%3$@.")
```

Run `make test`. Expected: the expectation fails.

- [x] **6.2 Note view.** Create `ios/App/ScheduleViews.swift` with `ScheduleNote(group: OutageGroup, state: ScheduleState?, now: Date)`, one secondary `.subheadline` line:
  - `.off(from, until)`: "YASNO, group 19.1: off 14:00–17:30." (times with `Text(_, style: .time)`).
  - `.emergency`: "YASNO, group %@: emergency outages, no end time."
  - `.clear`: "YASNO, group %@: no outage ahead."
  - No days and `failed`: "YASNO did not answer."
  - No state yet: nothing.

- [x] **6.3 Section.** In `ios/App/BatteryApp.swift` `SettingsScreen`:
  - Add `@State private var fromSchedule = Store().powerBackFromSchedule`, `@State private var outageGroup = Store().outageGroup`, `@State private var schedule = Store().schedule`.
  - First row of "Power back at": `NavigationLink { AddressScreen(group: outageGroup, onSave: saveGroup) } label: { LabeledContent("Address", value: outageGroup?.address ?? String(localized: "Not set")) }`.
  - Under "Grid returns", when `outageGroup` is set: `ScheduleNote(group:state:now:)`.
  - Day menu: show "Clear" only when `!fromSchedule`. Add "Use YASNO" when `!fromSchedule` and the stored schedule has an `.off` answer; it calls `useSchedule()`.
  - `setPowerBack` also sets `fromSchedule = false` and `store.powerBackFromSchedule = false`. Move its widget reload into `reloadEta()`.
  - Add the helpers:

```swift
    private func saveGroup(_ group: OutageGroup?) {
        outageGroup = group
        store.outageGroup = group
    }

    private func useSchedule() {
        store.powerBack = nil
        store.powerBackFromSchedule = false
        Task { await tickSchedule() }
    }

    private func tickSchedule() async {
        let changed = await ScheduleFeed.tick(store)
        schedule = store.schedule
        guard changed else { return }
        powerBack = store.powerBack
        fromSchedule = store.powerBackFromSchedule
        reloadEta()
    }

    private func pollSchedule() async {
        while !Task.isCancelled {
            await tickSchedule()
            try? await Task.sleep(for: Refresher.appPollInterval)
        }
    }

    private func reloadEta() {
        if checking { reloadAfterCheck = true } else { WidgetCenter.shared.reloadTimelines(ofKind: "eta") }
    }
```

  - Add `.task(id: outageGroup?.key) { await pollSchedule() }` next to `.task { await poll() }`, so a new group reads at once.

- [x] **6.4 Ukrainian.** Add to `ios/Shared/Localizable.xcstrings`, each with `"state": "translated"`. Run the `ukrainian-translation-review` skill on the values before committing.

| Key | uk |
|-----|----|
| `Address` | `Адреса` |
| `Not set` | `Не вказано` |
| `Use my location` | `Визначити за геолокацією` |
| `Street` | `Вулиця` |
| `House` | `Будинок` |
| `Remove address` | `Видалити адресу` |
| `Use YASNO` | `Брати з YASNO` |
| `Location is off. Type the street.` | `Геолокацію вимкнено. Введіть вулицю.` |
| `Could not find your street. Type it.` | `Не вдалося визначити вулицю. Введіть її.` |
| `No match. YASNO covers Kyiv city only.` | `Нічого не знайдено. YASNO обслуговує лише Київ.` |
| `YASNO did not answer.` | `YASNO не відповідає.` |
| `The app keeps only the group and the address text, not your location.` | `Застосунок зберігає лише групу й текст адреси, а не вашу геолокацію.` |
| `YASNO, group %@: off %@–%@.` | `YASNO, група %1$@: без світла %2$@–%3$@.` |
| `YASNO, group %@: emergency outages, no end time.` | `YASNO, група %@: аварійні відключення, час завершення невідомий.` |
| `YASNO, group %@: no outage ahead.` | `YASNO, група %@: найближчим часом відключень немає.` |

- [x] **6.5 Gate.** Run `make test`. Expected: exit 0.

- [ ] **6.6 Look.** In the `iPhone 18 Pro` simulator, run `xcrun simctl location booted set 50.4475,30.5219` (Khreshchatyk), open Address, tap "Use my location", and pick the house. Screenshot the "Power back at" section in English and Ukrainian with the YASNO line. Then set a manual time, check that it stays, and use "Use YASNO".

- [x] **6.7 Commit.** `feat: fill the power-back time from yasno`
