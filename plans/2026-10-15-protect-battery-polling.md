# Fewer requests to the battery

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** the battery's power output stops cutting off. The iOS app never sends `Bat.GetStatus`, the Stream Deck sends it at most every 5 minutes, the widgets on one device share one fetch, and the app polls every 30 s.

**Why:** the Stream Deck, the iPhone, the iPad and the widgets each poll the battery on their own, and the output cuts off now and then. Every timeout in the plugin log (14 Oct, 31 of them) is on `Bat.GetStatus`; `ES.GetStatus` never timed out. The Home Assistant integration says "`Bat.GetStatus` is suspected to trigger device resets on some Marstek firmwares", polls it every 300 s and skips it on firmwares known for resets ([taurgis/has-marstek-local-api](https://github.com/taurgis/has-marstek-local-api)).

**Architecture:**
- iOS: `ES.GetStatus` returns `bat_cap` (rated Wh, 5120). The app derives energy left as `bat_soc` % × `bat_cap`, which is 1 % (51 Wh) coarse and enough for the instant widget ETA.
- Widgets: in the widget process, a shared actor runs one refresh at a time. A refresh reuses a stored snapshot younger than 10 minutes.
- Stream Deck: reads `Bat.GetStatus` every 5 minutes, 60 s after a failed read, or once after a gap of over 2 minutes in readings (not on every retry while the battery is down). A failed read no longer fails the poll. Between reads, the estimator subtracts the energy it integrated from the AC power, so the ETA keeps falling smoothly.

**Tech stack:** Swift 5 mode, Swift Testing, WidgetKit (iOS); TypeScript, vitest (Stream Deck).

**Spec:** this plan. Device facts and fixtures: `plans/2026-10-12-streamdeck-battery-eta.md`.

## Global constraints

- Only `ES.GetStatus` and `Bat.GetStatus` are ever sent. The iOS app sends only `ES.GetStatus`.
- One request in flight per client. The Stream Deck keeps its 15 s `ES.GetStatus` poll.
- `streamdeck/src/core/` must not import `@elgato/streamdeck`.
- Branch `feat/ios-battery-widget`. Conventional Commits, one subject line, no co-author trailer. Do not stage `docs/research-marstek-warn-red-led.md`.
- Gates: from `ios/`, `make test`; from `streamdeck/`, `npm run typecheck && npm test`.

## Review focus

1. A friend's firmware without `bat_cap` in `ES.GetStatus`: the widget shows `ERROR`, never 0 Wh or a 0 h ETA. (Task 1 test.)
2. A stored snapshot written before this change still has `tempC`. It must decode, so the widget does not fall back to "Open the app". (Task 1 test.)
3. Settings fixed after a `SET IP` snapshot: the next widget refresh fetches and does not reuse the `.settings` snapshot. (Task 1 test.)
4. `Bat.GetStatus` times out while `ES.GetStatus` works: the Stream Deck key keeps updating with no error, and it asks `Bat.GetStatus` again only after 60 s. (Task 2 test.)
5. The Mac sleeps for 3 minutes: the first poll after waking reads `Bat.GetStatus` before it estimates, because the integrated energy has a hole. (Task 2 test.)

## Batches

- A: Task 1 (one `implementer` on Opus)
- B: Task 2 (one `implementer` on Opus)
- Then one fresh `reviewer` on the diff of both tasks.

Time: about 1 hour per task. Then a day of normal use to see whether the cuts stop.

---

## Task 1: iOS reads only ES.GetStatus and shares one widget fetch

**Files**
- Modify: `ios/Shared/MarstekProtocol.swift`, `ios/Shared/Reading.swift`, `ios/Shared/MarstekClient.swift`, `ios/Shared/Store.swift`, `ios/Widget/BatteryWidgets.swift`, `ios/App/BatteryApp.swift`
- Test: `ios/Tests/ProtocolTests.swift`, `ios/Tests/ClientTests.swift`, `ios/Tests/StoreTests.swift`, `ios/Tests/EstimateTests.swift`

**Interfaces**
- Produces: `EsStatus(socPct:ongridW:offgridW:ratedWh:)`, `Reading(time:es:)`, `Refresher.refresh(_:now:maxAge:fetch:)`, `Refresher.widgetMaxAge`, `SharedRefresh.shared.run(_:)`.
- Removes: `BatStatus`, `MarstekProtocol.batStatus`, `Reading.tempC`, `Reading(time:es:bat:)`.

- [x] **1.1 Tests first.** In `ios/Tests/ProtocolTests.swift`:
  - Delete `batReply`, `parsesTheBatReplyFromTheDevice` and `aNonPositiveRatedCapacityIsBad`.
  - Change the expectation in `parsesTheEsReplyFromTheDevice` to `EsStatus(socPct: 80, ongridW: -797, offgridW: 0, ratedWh: 5120)`.
  - Replace `acPowerIsOngridPlusOffgrid` with the tests below:

```swift
    @Test func acPowerIsOngridPlusOffgrid() {
        let reading = Reading(time: Date(timeIntervalSince1970: 0), es: EsStatus(socPct: 80, ongridW: 100, offgridW: 50, ratedWh: 5120))
        #expect(reading.acW == 150)
        #expect(reading.offgridW == 50)
    }

    @Test func energyLeftIsChargeTimesRatedCapacity() {
        let reading = Reading(time: Date(timeIntervalSince1970: 0), es: EsStatus(socPct: 80, ongridW: 0, offgridW: 0, ratedWh: 5120))
        #expect(reading.capacityWh == 4096)
        #expect(reading.ratedWh == 5120)
    }

    @Test func aMissingRatedCapacityIsBad() {
        #expect(throws: DeviceError.badReply("Reply has a missing field")) {
            try MarstekProtocol.esStatus(Data(#"{"id":2,"result":{"bat_soc":80,"ongrid_power":-797,"offgrid_power":0}}"#.utf8))
        }
    }

    @Test(arguments: [0.0, -5120.0])
    func aNonPositiveRatedCapacityIsBad(rated: Double) {
        let reply = #"{"id":2,"result":{"bat_soc":50,"ongrid_power":0,"offgrid_power":0,"bat_cap":\#(rated)}}"#
        #expect(throws: DeviceError.badReply("Reply has bat_cap \(rated)")) { try MarstekProtocol.esStatus(Data(reply.utf8)) }
    }

    @Test func aSnapshotStoredWithTemperatureStillDecodes() throws {
        let old = #"{"time":0,"socPct":80,"acW":400,"offgridW":0,"capacityWh":4121,"ratedWh":5120,"tempC":24}"#
        let reading = try JSONDecoder().decode(Reading.self, from: Data(old.utf8))
        #expect(reading.capacityWh == 4121)
    }
```

In `ios/Tests/ClientTests.swift`, replace `readingCombinesBothMethods`:

```swift
    @Test func aReadingAsksOnlyForEsStatus() async throws {
        var methods: [String] = []
        let fake = try await FakeBattery.start { request, _ in
            methods.append(request.method)
            return [#"{"id":\#(request.id),"result":{"bat_soc":80,"bat_cap":5120,"ongrid_power":-797,"offgrid_power":0}}"#]
        }
        defer { fake.stop() }
        let time = Date(timeIntervalSince1970: 0)
        let reading = try await client(fake).reading(at: time)
        #expect(reading == Reading(time: time, socPct: 80, acW: -797, offgridW: 0, capacityWh: 4096, ratedWh: 5120))
        #expect(methods == ["ES.GetStatus"])
    }
```

In `ios/Tests/EstimateTests.swift`, drop `, tempC: 24` from the `reading(...)` helper.

Append to `StoreTests` (inside the struct):

```swift
    @Test func aFreshSnapshotIsReused() async {
        let store = store()
        let good = reading(acW: 400)
        _ = await Refresher.refresh(store, now: good.time) { _ in good }
        var fetched = false
        let snapshot = await Refresher.refresh(store, now: good.time.addingTimeInterval(5 * 60), maxAge: 10 * 60) { _ in
            fetched = true
            return good
        }
        #expect(!fetched)
        #expect(snapshot.checkedAt == good.time)
    }

    @Test func anOldSnapshotIsFetchedAgain() async {
        let store = store()
        let good = reading(acW: 400)
        _ = await Refresher.refresh(store, now: good.time) { _ in good }
        var fetched = false
        _ = await Refresher.refresh(store, now: good.time.addingTimeInterval(11 * 60), maxAge: 10 * 60) { _ in
            fetched = true
            return good
        }
        #expect(fetched)
    }

    @Test func aSettingsSnapshotIsNotReused() async {
        let store = store(host: "")
        let now = Date(timeIntervalSince1970: 1_760_000_000)
        _ = await Refresher.refresh(store, now: now) { _ in reading(acW: 400) }
        store.settings = BatterySettings(host: "192.168.68.50", port: 30000, floorPct: 12)
        let snapshot = await Refresher.refresh(store, now: now.addingTimeInterval(60), maxAge: 10 * 60) { _ in reading(acW: 400) }
        #expect(snapshot.error == nil)
        #expect(snapshot.reading != nil)
    }

    @Test func concurrentRefreshesShareOneFetch() async {
        let gate = SharedRefresh()
        let counter = FetchCounter()
        async let a = gate.run { await counter.fetch() }
        async let b = gate.run { await counter.fetch() }
        async let c = gate.run { await counter.fetch() }
        _ = await (a, b, c)
        #expect(await counter.count == 1)
        _ = await gate.run { await counter.fetch() }
        #expect(await counter.count == 2)
    }
```

And below the struct:

```swift
actor FetchCounter {
    var count = 0

    func fetch() async -> Snapshot {
        count += 1
        try? await Task.sleep(for: .milliseconds(200))
        return Snapshot(reading: nil, error: .noLink, checkedAt: .now)
    }
}
```

Run `make test`. Expected: the build fails because `EsStatus` has no `ratedWh`.

- [x] **1.2 Protocol.** In `ios/Shared/MarstekProtocol.swift`:
  - Delete `BatStatus`, `batStatus(_:)` and `BatResult`.
  - Add `let ratedWh: Double` as the last field of `EsStatus`.
  - Add `case ratedWh = "bat_cap"` to `EsResult.CodingKeys`, with `let ratedWh: Double`.
  - Replace `esStatus`:

```swift
    static func esStatus(_ data: Data) throws -> EsStatus {
        let result = try decode(EsResult.self, data)
        guard result.ratedWh > 0 else { throw DeviceError.badReply("Reply has bat_cap \(result.ratedWh)") }
        return EsStatus(socPct: Int(result.socPct.rounded()), ongridW: result.ongridW, offgridW: result.offgridW, ratedWh: result.ratedWh)
    }
```

- [x] **1.3 Reading and client.** Replace `ios/Shared/Reading.swift`:

```swift
import Foundation

struct Reading: Codable, Equatable {
    var time: Date
    var socPct: Int
    var acW: Double
    var offgridW: Double
    var capacityWh: Double
    var ratedWh: Double
}

extension Reading {
    init(time: Date, es: EsStatus) {
        self.init(
            time: time, socPct: es.socPct, acW: es.ongridW + es.offgridW, offgridW: es.offgridW,
            capacityWh: Double(es.socPct) / 100 * es.ratedWh, ratedWh: es.ratedWh
        )
    }
}
```

In `ios/Shared/MarstekClient.swift`, replace `reading(at:)`. `gap` stays, because the retry uses it.

```swift
    func reading(at time: Date = .now) async throws -> Reading {
        Reading(time: time, es: try MarstekProtocol.esStatus(await call("ES.GetStatus")))
    }
```

- [x] **1.4 Shared refresh.** In `ios/Shared/Store.swift`, replace `Refresher.refresh` and add `widgetMaxAge` and `SharedRefresh`:

```swift
enum Refresher {
    static let widgetMaxAge: TimeInterval = 10 * 60

    static func refresh(
        _ store: Store,
        now: Date = .now,
        maxAge: TimeInterval = 0,
        fetch: (BatterySettings) async throws -> Reading = Refresher.live
    ) async -> Snapshot {
        let settings = store.settings
        if settings.problem == nil, let last = store.snapshot, last.error != .settings,
           (0..<maxAge).contains(now.timeIntervalSince(last.checkedAt)) {
            return last
        }
        var next = Snapshot(reading: store.snapshot?.reading, error: nil, checkedAt: now)
        if settings.problem != nil {
            next.error = .settings
        } else {
            do { next.reading = try await fetch(settings) } catch { next.error = FetchError(error) }
        }
        store.snapshot = next
        return next
    }

    static func live(_ settings: BatterySettings) async throws -> Reading {
        try await MarstekClient(host: settings.host, port: UInt16(settings.port)).reading()
    }
}

// The three widgets reload together; one fetch serves them all.
actor SharedRefresh {
    static let shared = SharedRefresh()
    private var running: Task<Snapshot, Never>?

    func run(_ work: @escaping @Sendable () async -> Snapshot) async -> Snapshot {
        if let running { return await running.value }
        let task = Task { await work() }
        running = task
        let snapshot = await task.value
        running = nil
        return snapshot
    }
}
```

- [x] **1.5 Widget and app.** In `ios/Widget/BatteryWidgets.swift`, replace `getTimeline`:

```swift
    func getTimeline(in context: Context, completion: @escaping (Timeline<BatteryEntry>) -> Void) {
        Task {
            let snapshot = await SharedRefresh.shared.run { await Refresher.refresh(Store(), maxAge: Refresher.widgetMaxAge) }
            let entry = BatteryEntry(date: .now, face: Face(snapshot, floorPct: Store().settings.floorPct))
            completion(Timeline(entries: [entry], policy: .after(.now.addingTimeInterval(15 * 60))))
        }
    }
```

In `ios/App/BatteryApp.swift` `poll()`, change `.seconds(15)` to `.seconds(30)`. The app keeps `maxAge` 0: an open app and **Save and check** always ask the battery.

Run `make test`. Expected: exit 0.

- [x] **1.6 Commit.** `git add ios && git commit -m "fix: read only es status on ios and share one widget fetch"`

---

## Task 2: Stream Deck reads Bat.GetStatus every 5 minutes

**Files**
- Modify: `streamdeck/src/core/poller.ts`, `streamdeck/src/core/estimator.ts`, `streamdeck/src/plugin.ts`, `README.md`, `CLAUDE.md`
- Test: `streamdeck/src/core/poller.test.ts`, `streamdeck/src/core/estimator.test.ts`

**Interfaces**
- Produces: optional `PollerDeps.warn?(message: string): void`.

- [ ] **2.1 Tests first.** In `streamdeck/src/core/estimator.test.ts`:
  - Give `Rig` a fifth constructor parameter, `readonly batEveryS = 30`.
  - Replace `if ((this.t / STEP_S) % 2 === 0)` with `if (this.t % this.batEveryS === 0)`.
  - Append:

```ts
test("between capacity reads the runtime follows the energy drawn", () => {
	const phase = { seconds: 1500, ongridW: 0, offgridW: 2000 };
	const every = new Rig(new Estimator(), 2500).run(phase).toEmptyH ?? 0;
	const rare = new Rig(new Estimator(), 2500, 0.88, 1.09, 300).run(phase).toEmptyH ?? 0;
	expect(Math.abs(rare - every)).toBeLessThan(0.02);
});

test("the discharge ratio is learned with a capacity read every 5 minutes", () => {
	const est = new Estimator();
	new Rig(est, 4500, 0.88, 1.2, 300).run({ seconds: 7200, ongridW: 0, offgridW: 800 });
	expect(est.learned.dischargeRatio).toBeGreaterThan(1.13);
});
```

In `streamdeck/src/core/poller.test.ts`:
- Add `failOnly?: string;` to `FakeDevice`, and change its reject line to `if (this.fail !== undefined && (this.failOnly === undefined || this.failOnly === method)) return Promise.reject(this.fail);`.
- Replace the tests `polls every 15 s and reads the capacity every second poll` and `the poll after a failed one reads the capacity again` with:

```ts
test("polls every 15 s and reads the capacity every 5 minutes", async () => {
	const { device, poller } = rig();
	await poller.kick();
	await vi.advanceTimersByTimeAsync(285_000);
	expect(device.calls).toEqual(["Bat.GetStatus", ...new Array<string>(20).fill("ES.GetStatus")]);
	await vi.advanceTimersByTimeAsync(15_000);
	expect(device.calls.slice(21)).toEqual(["Bat.GetStatus", "ES.GetStatus"]);
	poller.stop();
});

test("a failed capacity read keeps polling and retries the capacity after 60 s", async () => {
	const { device, published, poller } = rig();
	device.fail = new DeviceError("timeout", "No reply");
	device.failOnly = "Bat.GetStatus";
	await poller.kick();
	expect(device.calls).toEqual(["Bat.GetStatus", "ES.GetStatus"]);
	expect(published.at(-1)?.error).toBeUndefined();
	expect(published.at(-1)?.estimate?.socPct).toBe(82);

	await vi.advanceTimersByTimeAsync(45_000);
	expect(device.calls.slice(2)).toEqual(["ES.GetStatus", "ES.GetStatus", "ES.GetStatus"]);
	await vi.advanceTimersByTimeAsync(15_000);
	expect(device.calls.slice(5)).toEqual(["Bat.GetStatus", "ES.GetStatus"]);
	poller.stop();
});

test("after two minutes without a reading the next poll reads the capacity first", async () => {
	const { device, poller } = rig();
	await poller.kick();
	device.fail = new DeviceError("timeout", "No reply");
	await vi.advanceTimersByTimeAsync(105_000);
	device.fail = undefined;
	const before = device.calls.length;
	await vi.advanceTimersByTimeAsync(60_000);
	expect(device.calls.slice(before)).toEqual(["Bat.GetStatus", "ES.GetStatus"]);
	poller.stop();
});

test("while the battery is down the capacity is asked at most once a minute", async () => {
	const { device, poller } = rig();
	device.fail = new DeviceError("timeout", "No reply");
	await poller.kick();
	await poller.kick();
	await poller.kick();
	expect(device.calls).toEqual(["Bat.GetStatus", "ES.GetStatus", "ES.GetStatus", "ES.GetStatus"]);
	poller.stop();
});
```

Run `npm test` from `streamdeck/`. Expected: the new tests fail.

- [ ] **2.2 Estimator.** In `streamdeck/src/core/estimator.ts`:
  - Add `const BAT_GAP_S = 600;` under `GAP_S`, and in `battery()` use `BAT_GAP_S` in place of `GAP_S`.
  - Add the field `#movedWh = 0;`. Set `this.#movedWh = 0;` in `battery()` right after `this.#bat = bat;`.
  - In `sample()`, after `this.#lastT = es.t;`, add:

```ts
		if (this.#bat !== undefined) {
			const afterBatS = Math.max(0, Math.min(dt, (es.t - this.#bat.t) / 1000));
			const ratio = acW < 0 ? this.#learned.chargeRatio : this.#learned.dischargeRatio;
			this.#movedWh += (acW * ratio * afterBatS) / 3600;
		}
```

  - Add the method below and use it for every `bat.capacityWh` read in `#toFull()` (two places) and `#toEmpty()` (one place). `battery()` keeps the raw `bat.capacityWh` for calibration.

```ts
	#capacityWh(bat: BatStatus): number {
		return clamp(bat.capacityWh - this.#movedWh, 0, bat.ratedWh);
	}
```

- [ ] **2.3 Poller.** In `streamdeck/src/core/poller.ts`:
  - Replace `BAT_EVERY` and `BAT_MAX_AGE_MS` with `BAT_EVERY_MS = 300_000`, `BAT_RETRY_MS = 60_000` and `ES_GAP_MS = 120_000`.
  - Replace the fields `#ticks` and `#batAt` with `#batTriedAt = Number.NEGATIVE_INFINITY;`, `#batFailed = false;` and `#esAt = Number.NEGATIVE_INFINITY;`.
  - In `reconfigure()`, replace `this.#ticks = 0;` with `this.#batTriedAt = Number.NEGATIVE_INFINITY;` and `this.#esAt = Number.NEGATIVE_INFINITY;`.
  - In the catch of `#tick`, delete `this.#ticks = 0;`.
  - Add `warn?(message: string): void;` to `PollerDeps`.
  - Replace the block from `if (this.#ticks % BAT_EVERY …` through `this.#set(...)` with:

```ts
			const now = this.deps.now();
			const batWaitMs = this.#batFailed ? BAT_RETRY_MS : BAT_EVERY_MS;
			const gap = now - this.#esAt > ES_GAP_MS && this.#batTriedAt <= this.#esAt;
			if (now - this.#batTriedAt >= batWaitMs || gap) {
				this.#batTriedAt = now;
				try {
					const reply = await device.call("Bat.GetStatus");
					if (stale()) return;
					const bat = toBatStatus(reply, this.deps.now());
					this.deps.estimator.battery(bat);
					this.#tempC = bat.tempC;
					this.#batFailed = false;
				} catch (err) {
					if (stale()) return;
					this.#batFailed = true;
					this.deps.warn?.(`Bat.GetStatus failed: ${err instanceof Error ? err.message : "Unknown error"}`);
				}
			}
			const reply = await device.call("ES.GetStatus");
			if (stale()) return;
			const es = toEsStatus(reply, this.deps.now());

			this.#fails = 0;
			this.#esAt = es.t;
			this.#set({ estimate: this.deps.estimator.sample(es), tempC: this.#tempC });
```

In `streamdeck/src/plugin.ts`, add `warn: (message) => streamDeck.logger.warn(message),` to the `Poller` deps.

Run `npm run typecheck && npm test`. Expected: exit 0. The older tests keep their call lists, because a fresh poller, a reconfigure and an 8-hour sleep all read the capacity first.

- [ ] **2.4 Docs.**
  - `README.md` line 12 becomes: `The plugin only reads. It sends \`ES.GetStatus\` every 15 s and \`Bat.GetStatus\` every 5 minutes, and never a command that changes the battery.`
  - In `CLAUDE.md`, the first constraint becomes: `- The plugin only reads: \`ES.GetStatus\` every 15 s, \`Bat.GetStatus\` at most every 5 min (it is suspected to reset some firmwares). The iOS app sends only \`ES.GetStatus\`. Never send a method that writes.`

- [ ] **2.5 Commit.** `git add streamdeck/src README.md CLAUDE.md && git commit -m "fix: read battery capacity every 5 minutes on the stream deck"`

- [ ] **2.6 Owner: deploy and watch (10 minutes, then a day).**
  1. From `streamdeck/`: `npm run build && streamdeck restart com.mlapin.marstek`.
  2. Reinstall the iOS app on the iPhone and iPad.
  3. Over the next day, note any power cut with its time. The plugin log (`streamdeck/com.mlapin.marstek.sdPlugin/logs/`) shows each `Bat.GetStatus failed`, so a cut can be matched to a request.
