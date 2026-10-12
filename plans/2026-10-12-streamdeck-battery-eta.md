# Stream Deck battery keys for the Marstek Venus E 3.0

**Goal:** two Stream Deck keys that read the battery over the LAN. One shows the charge percent. The other shows the time until full while charging and the time until empty while discharging.

**Architecture:** the plugin's Node process polls the battery's Open API over UDP. `src/core/` holds the protocol, the UDP client, the estimator and the key views; it imports nothing from the Stream Deck SDK, so vitest covers it and a later web dashboard can reuse it. `src/actions/` and `src/plugin.ts` are a thin SDK layer. One poller feeds all keys.

**Stack:** TypeScript, `@elgato/streamdeck` 3.0.2 (manifest `SDKVersion` 3, Node 24, Stream Deck 7.1+; 7.5.1 is installed), `@elgato/cli` 1.10.2, rollup, vitest, `node:dgram`.

**Layout:** the plugin project lives in `streamdeck/` inside this repo. Build config, key SVG style and the property inspector follow `~/Development/personal/my_projects/streamdeck-ipscut-visitors`.

## Device facts (measured 2026-10-12, firmware V150)

- The battery answers at `192.168.68.50:30000`. Replies arrive in 0.1–0.4 s. `Marstek.GetDevice` discovery gets no reply, so the address is a setting.
- `ES.GetStatus` returns `bat_soc` (whole %), `ongrid_power` (W, negative while charging from the grid), `offgrid_power` (W, backup socket), `total_grid_input_energy` (Wh). It has no `bat_power` field.
- `Bat.GetStatus` returns `bat_capacity` (Wh remaining, moves in ~5 Wh steps), `rated_capacity` (5120 Wh), `bat_temp` (°C).
- While drawing 797 W the battery stored 695 W over 8 minutes: charge ratio 0.88.
- `ES.GetMode` reports `Manual` while the app shows UPS. The plugin does not read the mode.
- 2 requests every 10 s ran for 8 minutes with one reply that had no `result`.
- The API has no authentication and the firmware answers one request at a time.

## How the ETA works

Battery AC power is `ongrid_power + offgrid_power`, positive while discharging. Task 7 checks this sum on the real device.

**Time until empty.** Usable energy is `bat_capacity − floor% × rated_capacity`, divided by the learned discharge ratio (battery Wh drained per AC Wh delivered, default 1.09). The load forecast is `L(s) = mid + (fast − mid)·e^(−s/10 min)`: `fast` is a 1-minute average of the median of the last 3 readings, `mid` is a 15-minute average. The ETA is the time `T` at which the integral of `L` equals the usable energy. A kettle moves `fast` but its effect decays in the forecast, so a 10-hour estimate barely moves; a sustained change reaches `mid` within 15–30 minutes; with 5 minutes left the current load dominates.

**Time until full.** Charge power is a 2-minute average. Stored power is charge power × the learned charge ratio (default 0.88). Above 90 % the estimator keeps a 10-entry table of "charge power at this percent ÷ charge power below 90 %", learned from every charge that passes 90 %, and sums the time bucket by bucket. The table starts at 1.0, so the first charge to 100 % shows an optimistic tail and later ones do not.

**Ratios** are learned from the device's own counter: every 150 AC Wh the estimator compares the change of `bat_capacity` with the AC energy it integrated.

**While idle on grid,** the ETA key shows a projection labelled `IF OUTAGE`: usable energy ÷ the 15-minute average of the backup-socket load, or ÷ the typical discharge load from earlier outages when the socket is idle.

Learned values (two ratios, taper table, typical load) persist in the plugin's global settings.

## Global constraints

- The plugin sends only `ES.GetStatus` and `Bat.GetStatus`. It never sends a method that writes.
- One request in flight, 1 s between requests, one poll every 15 s (`Bat.GetStatus` every second poll), 60 s after 3 failed polls.
- `src/core/` imports nothing from `@elgato/streamdeck`.
- No `any`, no `unknown`, no unnecessary comments. `npm run typecheck` and `npm test` pass after every task.
- Conventional Commits, one subject line. Work on branch `feat/streamdeck-battery-eta`.
- All commands run from `streamdeck/`.

## Review focus

1. Mac asleep or off the home network: keys keep the last value dimmed, show `NO LINK` after 3 failed polls, and recover within one poll of waking. (Task 5 test.)
2. macOS Local Network permission denied (`EHOSTUNREACH`): the key shows `LAN` on the first failure. (Tasks 2 and 5 tests.)
3. A reply with no `result` or a missing field counts as a failed poll; the estimator never receives zeros. (Task 2 test.)
4. A late datagram with another request's id is ignored. (Task 2 test.)
5. Battery at the floor or at 100 %: the keys show `0m` and `FULL`, never `NaN` or `Infinity`. (Tasks 3 and 4 tests.)

---

## Task 1: Walking skeleton — a key that reads the battery from inside Stream Deck

Proves the two unverified points before any real code: `node:dgram` works in the plugin runtime, and macOS lets the plugin reach a LAN address.

**Files**
- Create: `.gitignore`, `CLAUDE.md` (repo root)
- Create: `streamdeck/package.json`, `streamdeck/tsconfig.json`, `streamdeck/rollup.config.mjs`
- Create: `streamdeck/com.mlapin.marstek.sdPlugin/manifest.json`, `…/imgs/**`, `…/ui/sdpi-components.js`
- Create: `streamdeck/src/plugin.ts`

- [ ] **1.1 Init the repo.** From the repo root:

```bash
git init -b main
printf 'node_modules/\n*.sdPlugin/bin/\n*.sdPlugin/logs/\n*.streamDeckPlugin\n.DS_Store\n' > .gitignore
git add .gitignore plans && git commit -m "docs: add stream deck battery plan"
git switch -c feat/streamdeck-battery-eta
```

- [ ] **1.2 Write `CLAUDE.md`** at the repo root:

```markdown
# CLAUDE.md

Tools for a Marstek Venus E 3.0 home battery. `streamdeck/` is a Stream Deck plugin
(SDK 3, Node 24, TypeScript) that polls the battery's Open API over UDP on the LAN.

## Commands (run from `streamdeck/`)

`npm run build` · `npm run watch` · `npm run typecheck` · `npm test` ·
`MARSTEK_HOST=192.168.68.50 npm run probe`

## Constraints

- The plugin only reads: `ES.GetStatus` and `Bat.GetStatus`. Never send a method that writes.
- The firmware answers one UDP request at a time. Keep one request in flight and the 15 s poll.
- `src/core/` must not import `@elgato/streamdeck`.
- Device facts and the ETA design: `plans/2026-10-12-streamdeck-battery-eta.md`.
```

- [ ] **1.3 Create `streamdeck/package.json`** and install:

```json
{
	"name": "streamdeck-marstek",
	"version": "0.1.0",
	"private": true,
	"type": "module",
	"scripts": {
		"build": "rollup -c",
		"watch": "rollup -c -w --watch.onEnd=\"streamdeck restart com.mlapin.marstek\"",
		"typecheck": "tsc --noEmit",
		"test": "vitest run",
		"probe": "tsx src/probe.ts"
	}
}
```

```bash
npm i @elgato/streamdeck@^3.0.2
npm i -D @elgato/cli@^1.10.2 @rollup/plugin-commonjs @rollup/plugin-node-resolve @rollup/plugin-typescript @types/node rollup tslib typescript vitest tsx
```

- [ ] **1.4 Create `streamdeck/tsconfig.json`:**

```json
{
	"compilerOptions": {
		"lib": ["ES2022"],
		"types": ["node"],
		"module": "ES2022",
		"moduleResolution": "Bundler",
		"target": "ES2022",
		"strict": true,
		"noImplicitOverride": true,
		"noUnusedLocals": true,
		"rootDir": "src",
		"sourceMap": true,
		"skipLibCheck": true
	},
	"include": ["src/**/*"]
}
```

- [ ] **1.5 Copy `rollup.config.mjs`** from `streamdeck-ipscut-visitors/rollup.config.mjs` and change one line to `const sdPlugin = "com.mlapin.marstek.sdPlugin";`.

- [ ] **1.6 Copy assets** from the existing plugin:

```bash
SRC="$HOME/Development/personal/my_projects/streamdeck-ipscut-visitors/com.mlapin.posthog-visitors.sdPlugin"
DST=com.mlapin.marstek.sdPlugin
mkdir -p $DST/imgs/actions $DST/ui
cp -R "$SRC/imgs/plugin" $DST/imgs/plugin
cp -R "$SRC/imgs/actions/visitors" $DST/imgs/actions/battery
cp "$SRC/ui/sdpi-components.js" $DST/ui/
```

- [ ] **1.7 Create `manifest.json`** with one action for now:

```json
{
	"Name": "Marstek Battery",
	"Version": "0.1.0.0",
	"Author": "Nikita Lapin",
	"Description": "Shows the charge level, time until full and time until empty of a Marstek Venus battery.",
	"Category": "Marstek",
	"CategoryIcon": "imgs/plugin/category-icon",
	"Icon": "imgs/plugin/marketplace",
	"CodePath": "bin/plugin.js",
	"SDKVersion": 3,
	"UUID": "com.mlapin.marstek",
	"Nodejs": { "Version": "24", "Debug": "enabled" },
	"Software": { "MinimumVersion": "7.1" },
	"OS": [
		{ "Platform": "mac", "MinimumVersion": "12" },
		{ "Platform": "windows", "MinimumVersion": "10" }
	],
	"Actions": [
		{
			"Name": "Battery level",
			"UUID": "com.mlapin.marstek.level",
			"Icon": "imgs/actions/battery/icon",
			"Tooltip": "Charge percent and current power.",
			"Controllers": ["Keypad"],
			"States": [{ "Image": "imgs/actions/battery/key", "TitleAlignment": "middle" }]
		}
	]
}
```

- [ ] **1.8 Write the skeleton `src/plugin.ts`:**

```ts
import streamDeck, { action, SingletonAction, type WillAppearEvent } from "@elgato/streamdeck";
import dgram from "node:dgram";

const HOST = "192.168.68.50";
const PORT = 30000;

function readSoc(): Promise<string> {
	return new Promise((resolve) => {
		const socket = dgram.createSocket("udp4");
		const done = (text: string) => {
			clearTimeout(timer);
			socket.close();
			resolve(text);
		};
		const timer = setTimeout(() => done("timeout"), 3000);
		socket.on("error", (err) => done(err.message));
		socket.on("message", (data) => {
			const match = /"bat_soc":\s*(\d+)/.exec(data.toString("utf8"));
			done(match ? `${match[1]}%` : "no soc");
		});
		socket.send(JSON.stringify({ id: 1, method: "ES.GetStatus", params: { id: 0 } }), PORT, HOST, (err) => {
			if (err) done(err.message);
		});
	});
}

@action({ UUID: "com.mlapin.marstek.level" })
class LevelKey extends SingletonAction {
	override async onWillAppear(ev: WillAppearEvent): Promise<void> {
		if (!ev.action.isKey()) return;
		const text = await readSoc();
		streamDeck.logger.info(`skeleton read: ${text}`);
		await ev.action.setTitle(text);
	}
}

streamDeck.actions.registerAction(new LevelKey());
await streamDeck.connect();
```

- [ ] **1.9 Build, link, run:**

```bash
npm run typecheck && npm run build
npx streamdeck dev
npx streamdeck link com.mlapin.marstek.sdPlugin
npx streamdeck restart com.mlapin.marstek
```

Drag "Battery level" onto a key. If macOS asks to let Stream Deck find devices on the local network, allow it.

- [ ] **1.10 Gate.** The key title shows the percent, for example `83%`. If it shows `EHOSTUNREACH` or `No route to host`, open System Settings → Privacy & Security → Local Network, enable Stream Deck, restart the plugin. If it still fails, stop and report: the design then needs a collector process outside Stream Deck.

- [ ] **1.11 Commit:** `git add -A && git commit -m "feat: add stream deck skeleton that reads battery soc over udp"`

---

## Task 2: Protocol and UDP client

**Files**
- Create: `streamdeck/src/core/types.ts`, `protocol.ts`, `client.ts`
- Test: `streamdeck/src/core/protocol.test.ts`, `client.test.ts`

**Produces**
- `types.ts`: `EsStatus`, `BatStatus`, `Mode`, `Estimate`, `Learned`
- `protocol.ts`: `Json`, `JsonObject`, `ProtocolError`, `request(id, method): string`, `envelope(text): { id: number; body: JsonObject }`, `resultOf(body): JsonObject`, `toEsStatus(result, t): EsStatus`, `toBatStatus(result, t): BatStatus`
- `client.ts`: `DeviceErrorKind`, `DeviceError`, `Device`, `MarstekClient`

- [ ] **2.1 Write `types.ts`:**

```ts
export type EsStatus = { t: number; socPct: number; ongridW: number; offgridW: number };

export type BatStatus = { t: number; capacityWh: number; ratedWh: number; tempC: number };

export type Mode = "charging" | "discharging" | "idle";

export type Estimate = {
	mode: Mode;
	socPct: number;
	batteryAcW: number;
	toFullH: number | null;
	toEmptyH: number | null;
	projected: boolean;
	warmingUp: boolean;
};

export type Learned = {
	chargeRatio: number;
	dischargeRatio: number;
	typicalLoadW: number | null;
	taper: number[];
};
```

`t` is epoch milliseconds. `batteryAcW` is positive while discharging. `projected` is true when `toEmptyH` is the on-grid "if the power fails now" figure.

- [ ] **2.2 Write the failing `protocol.test.ts`:**

```ts
import { expect, test } from "vitest";

import { envelope, ProtocolError, request, resultOf, toBatStatus, toEsStatus } from "./protocol";

const ES = `{"id":2,"src":"VenusE 3.0-bc2a3314ce8d","result":{"id":0,"bat_soc":80,"bat_cap":5120,"pv_power":0,"ongrid_power":-797,"offgrid_power":0,"total_grid_input_energy":47029}}`;
const BAT = `{"id":3,"src":"VenusE 3.0-bc2a3314ce8d","result":{"id":0,"soc":80,"charg_flag":true,"dischrg_flag":true,"bat_temp":24.0,"bat_capacity":4121.0,"rated_capacity":5120.0}}`;

test("request addresses instance 0", () => {
	expect(JSON.parse(request(7, "ES.GetStatus"))).toEqual({ id: 7, method: "ES.GetStatus", params: { id: 0 } });
});

test("parses the ES.GetStatus reply captured from the device", () => {
	const { id, body } = envelope(ES);
	expect(id).toBe(2);
	expect(toEsStatus(resultOf(body), 1000)).toEqual({ t: 1000, socPct: 80, ongridW: -797, offgridW: 0 });
});

test("parses the Bat.GetStatus reply captured from the device", () => {
	expect(toBatStatus(resultOf(envelope(BAT).body), 1000)).toEqual({ t: 1000, capacityWh: 4121, ratedWh: 5120, tempC: 24 });
});

test("a reply with no result is a protocol error", () => {
	expect(() => resultOf(envelope(`{"id":2,"src":"x"}`).body)).toThrow(ProtocolError);
});

test("a device error carries its code", () => {
	expect(() => resultOf(envelope(`{"id":2,"error":{"code":-32601,"message":"Method not found"}}`).body)).toThrow(/-32601/);
});

test("a missing field is a protocol error, never a zero", () => {
	expect(() => toEsStatus({ bat_soc: 80, ongrid_power: -797 }, 0)).toThrow(/offgrid_power/);
});

test("non-JSON is a protocol error", () => {
	expect(() => envelope("garbage")).toThrow(ProtocolError);
});
```

- [ ] **2.3 Run `npm test`.** Expected: FAIL, cannot resolve `./protocol`.

- [ ] **2.4 Write `protocol.ts`:**

```ts
import type { BatStatus, EsStatus } from "./types";

export type Json = string | number | boolean | null | Json[] | { [key: string]: Json };
export type JsonObject = { [key: string]: Json };

export class ProtocolError extends Error {}

export function request(id: number, method: string): string {
	return JSON.stringify({ id, method, params: { id: 0 } });
}

export function envelope(text: string): { id: number; body: JsonObject } {
	let body: Json;
	try {
		body = JSON.parse(text) as Json;
	} catch {
		throw new ProtocolError("Reply is not JSON");
	}
	if (!isObject(body) || typeof body.id !== "number") throw new ProtocolError("Reply has no id");
	return { id: body.id, body };
}

export function resultOf(body: JsonObject): JsonObject {
	const { error, result } = body;
	if (isObject(error)) throw new ProtocolError(`Device error ${String(error.code)}: ${String(error.message)}`);
	if (!isObject(result)) throw new ProtocolError("Reply has no result");
	return result;
}

export function toEsStatus(result: JsonObject, t: number): EsStatus {
	return {
		t,
		socPct: num(result, "bat_soc"),
		ongridW: num(result, "ongrid_power"),
		offgridW: num(result, "offgrid_power"),
	};
}

export function toBatStatus(result: JsonObject, t: number): BatStatus {
	return {
		t,
		capacityWh: num(result, "bat_capacity"),
		ratedWh: num(result, "rated_capacity"),
		tempC: num(result, "bat_temp"),
	};
}

function isObject(value: Json | undefined): value is JsonObject {
	return typeof value === "object" && value !== null && !Array.isArray(value);
}

function num(result: JsonObject, key: string): number {
	const value = result[key];
	if (typeof value !== "number" || !Number.isFinite(value)) throw new ProtocolError(`Reply has no ${key}`);
	return value;
}
```

- [ ] **2.5 Run `npm test`.** Expected: 7 passed.

- [ ] **2.6 Write the failing `client.test.ts`.** It talks to a fake device on `127.0.0.1`:

```ts
import dgram from "node:dgram";
import { afterEach, expect, test } from "vitest";

import { DeviceError, MarstekClient } from "./client";

type Incoming = { id: number; method: string };
type Fake = { port: number; seen: Incoming[]; close(): void };

const open: Array<{ close(): void }> = [];
afterEach(() => {
	for (const item of open.splice(0)) item.close();
});

async function fake(reply: (msg: Incoming, attempt: number) => string[]): Promise<Fake> {
	const server = dgram.createSocket("udp4");
	const seen: Incoming[] = [];
	server.on("message", (data, from) => {
		const msg = JSON.parse(data.toString("utf8")) as Incoming;
		seen.push(msg);
		for (const out of reply(msg, seen.length)) server.send(out, from.port, from.address);
	});
	await new Promise<void>((done) => server.bind(0, "127.0.0.1", done));
	const device = { port: server.address().port, seen, close: () => server.close() };
	open.push(device);
	return device;
}

function client(port: number): MarstekClient {
	const made = new MarstekClient("127.0.0.1", port, { timeoutMs: 60, gapMs: 5 });
	open.push(made);
	return made;
}

test("returns the result of the matching reply", async () => {
	const device = await fake((msg) => [`{"id":${msg.id},"result":{"bat_soc":80}}`]);
	expect(await client(device.port).call("ES.GetStatus")).toEqual({ bat_soc: 80 });
	expect(device.seen[0].method).toBe("ES.GetStatus");
});

test("ignores a late reply that carries another id", async () => {
	const device = await fake((msg) => [`{"id":${msg.id + 100},"src":"stale"}`, `{"id":${msg.id},"result":{"bat_soc":81}}`]);
	expect(await client(device.port).call("ES.GetStatus")).toEqual({ bat_soc: 81 });
});

test("retries once after a timeout", async () => {
	const device = await fake((msg, attempt) => (attempt === 1 ? [] : [`{"id":${msg.id},"result":{"bat_soc":82}}`]));
	expect(await client(device.port).call("ES.GetStatus")).toEqual({ bat_soc: 82 });
	expect(device.seen).toHaveLength(2);
});

test("two timeouts reject with kind timeout", async () => {
	const device = await fake(() => []);
	const failure = await client(device.port).call("ES.GetStatus").catch((err: Error) => err);
	expect(failure).toBeInstanceOf(DeviceError);
	expect((failure as DeviceError).kind).toBe("timeout");
});

test("a reply with no result rejects with kind protocol", async () => {
	const device = await fake((msg) => [`{"id":${msg.id},"src":"x"}`]);
	const failure = await client(device.port).call("ES.GetStatus").catch((err: Error) => err);
	expect((failure as DeviceError).kind).toBe("protocol");
});

test("calls run one at a time", async () => {
	const device = await fake((msg) => [`{"id":${msg.id},"result":{"n":${msg.id}}}`]);
	const made = client(device.port);
	const [a, b] = await Promise.all([made.call("Bat.GetStatus"), made.call("ES.GetStatus")]);
	expect([a.n, b.n]).toEqual([1, 2]);
	expect(device.seen.map((msg) => msg.method)).toEqual(["Bat.GetStatus", "ES.GetStatus"]);
});

test("EHOSTUNREACH maps to kind blocked", () => {
	expect(DeviceError.fromSend(Object.assign(new Error("send EHOSTUNREACH"), { code: "EHOSTUNREACH" })).kind).toBe("blocked");
	expect(DeviceError.fromSend(Object.assign(new Error("send ENETDOWN"), { code: "ENETDOWN" })).kind).toBe("network");
});
```

- [ ] **2.7 Run `npm test`.** Expected: FAIL, cannot resolve `./client`.

- [ ] **2.8 Write `client.ts`:**

```ts
import dgram from "node:dgram";

import { envelope, type JsonObject, ProtocolError, request, resultOf } from "./protocol";

export type DeviceErrorKind = "timeout" | "blocked" | "network" | "protocol";

export class DeviceError extends Error {
	constructor(
		readonly kind: DeviceErrorKind,
		message: string,
	) {
		super(message);
	}

	static fromSend(err: NodeJS.ErrnoException): DeviceError {
		const blocked = err.code === "EHOSTUNREACH" || err.code === "EHOSTDOWN";
		return new DeviceError(blocked ? "blocked" : "network", err.message);
	}
}

export interface Device {
	call(method: string): Promise<JsonObject>;
	close(): void;
}

type Options = { timeoutMs?: number; gapMs?: number };

export class MarstekClient implements Device {
	readonly #timeoutMs: number;
	readonly #gapMs: number;
	#socket?: dgram.Socket;
	#nextId = 1;
	#queue: Promise<void> = Promise.resolve();

	constructor(
		private readonly host: string,
		private readonly port: number,
		options: Options = {},
	) {
		this.#timeoutMs = options.timeoutMs ?? 3000;
		this.#gapMs = options.gapMs ?? 1000;
	}

	call(method: string): Promise<JsonObject> {
		const run = this.#queue.then(() =>
			this.#attempt(method).catch((err: Error) => {
				if (err instanceof DeviceError && err.kind === "timeout") return this.#attempt(method);
				throw err;
			}),
		);
		const pause = () => new Promise<void>((done) => setTimeout(done, this.#gapMs));
		this.#queue = run.then(pause, pause);
		return run;
	}

	close(): void {
		this.#socket?.close();
		this.#socket = undefined;
	}

	#open(): dgram.Socket {
		if (this.#socket !== undefined) return this.#socket;
		const socket = dgram.createSocket("udp4");
		socket.on("error", () => {
			if (this.#socket === socket) this.close();
		});
		this.#socket = socket;
		return socket;
	}

	#attempt(method: string): Promise<JsonObject> {
		const socket = this.#open();
		const id = this.#nextId++;

		return new Promise((resolve, reject) => {
			const settle = (act: () => void) => {
				clearTimeout(timer);
				socket.off("message", onMessage);
				act();
			};
			const onMessage = (data: Buffer) => {
				try {
					const reply = envelope(data.toString("utf8"));
					if (reply.id !== id) return;
					const result = resultOf(reply.body);
					settle(() => resolve(result));
				} catch (err) {
					const message = err instanceof ProtocolError ? err.message : "Bad reply";
					settle(() => reject(new DeviceError("protocol", message)));
				}
			};
			const timer = setTimeout(
				() => settle(() => reject(new DeviceError("timeout", `No reply to ${method}`))),
				this.#timeoutMs,
			);

			socket.on("message", onMessage);
			socket.send(request(id, method), this.port, this.host, (err) => {
				if (err) settle(() => reject(DeviceError.fromSend(err)));
			});
		});
	}
}
```

- [ ] **2.9 Run `npm test && npm run typecheck`.** Expected: 14 passed, no type errors.

- [ ] **2.10 Commit:** `git add -A && git commit -m "feat: add marstek open api protocol and udp client"`

---

## Task 3: Estimator

**Files**
- Create: `streamdeck/src/core/estimator.ts`
- Test: `streamdeck/src/core/estimator.test.ts`

**Consumes:** `EsStatus`, `BatStatus`, `Estimate`, `Learned`, `Mode` from `types.ts`.

**Produces:** `defaultLearned(): Learned`, `solveRuntime(acWh, nowW, baseW): number`, `class Estimator` with `constructor(learned?, floorPct?)`, `restore(learned)`, `learned` (getter, a copy), `floorPct` (settable), `battery(bat: BatStatus): void`, `sample(es: EsStatus): Estimate`.

- [ ] **3.1 Write the failing `estimator.test.ts`:**

```ts
import { expect, test } from "vitest";

import { defaultLearned, Estimator, solveRuntime } from "./estimator";
import type { Estimate, Learned } from "./types";

const RATED = 5120;
const STEP_S = 15;

type Phase = { seconds: number; ongridW: number; offgridW?: number };

class Rig {
	t = 0;
	last!: Estimate;
	constructor(
		readonly est: Estimator,
		public capacityWh: number,
		readonly storeRatio = 0.88,
		readonly drainRatio = 1.09,
	) {}

	run(...phases: Phase[]): Estimate {
		for (const phase of phases) {
			for (let elapsed = 0; elapsed < phase.seconds; elapsed += STEP_S) {
				const offgridW = phase.offgridW ?? 0;
				const acW = phase.ongridW + offgridW;
				const ratio = acW < 0 ? this.storeRatio : this.drainRatio;
				if (this.t > 0) this.capacityWh = Math.min(RATED, this.capacityWh - (acW * ratio * STEP_S) / 3600);
				if ((this.t / STEP_S) % 2 === 0) {
					this.est.battery({ t: this.t * 1000, capacityWh: this.capacityWh, ratedWh: RATED, tempC: 24 });
				}
				this.last = this.est.sample({
					t: this.t * 1000,
					socPct: Math.floor((this.capacityWh / RATED) * 100),
					ongridW: phase.ongridW,
					offgridW,
				});
				this.t += STEP_S;
			}
		}
		return this.last;
	}
}

function learned(patch: Partial<Learned>): Learned {
	return { ...defaultLearned(), ...patch };
}

test("solveRuntime equals energy over load when the load is steady", () => {
	expect(solveRuntime(3000, 300, 300)).toBeCloseTo(10, 3);
});

test("solveRuntime follows the current load when little energy is left", () => {
	const hours = solveRuntime(91.7, 2000, 300);
	expect(hours).toBeGreaterThan(91.7 / 2000);
	expect(hours).toBeLessThan(0.06);
});

test("solveRuntime returns 0 for no energy and caps at 240 h", () => {
	expect(solveRuntime(0, 300, 300)).toBe(0);
	expect(solveRuntime(1e9, 300, 300)).toBe(240);
});

test("time to full uses the charge ratio measured on the device", () => {
	const rig = new Rig(new Estimator(), 4244);
	const first = rig.run({ seconds: 15, ongridW: -797 });
	expect(first.mode).toBe("charging");
	expect(first.toFullH).toBeCloseTo((RATED - 4244) / (797 * 0.88), 2);
	expect(first.toEmptyH).toBeNull();
});

test("time to full slows down through a learned taper", () => {
	const taper = [1, 1, 1, 1, 1, 0.5, 0.5, 0.5, 0.5, 0.5];
	const rig = new Rig(new Estimator(learned({ taper })), RATED * 0.9);
	const got = rig.run({ seconds: 15, ongridW: -800 });
	expect(got.toFullH).toBeCloseTo((5 * 51.2) / 704 + (5 * 51.2) / 352, 2);
});

test("inside the taper the remaining buckets scale from the current power", () => {
	const taper = [1, 1, 1, 1, 1, 0.5, 0.5, 0.5, 0.5, 0.5];
	const rig = new Rig(new Estimator(learned({ taper })), RATED * 0.97);
	const got = rig.run({ seconds: 15, ongridW: -400 });
	expect(got.toFullH).toBeCloseTo((3 * 51.2) / 352, 2);
});

test("a full battery reports zero hours, not NaN", () => {
	const rig = new Rig(new Estimator(), RATED);
	expect(rig.run({ seconds: 15, ongridW: -100 }).toFullH).toBeCloseTo(0, 6);
});

test("a kettle does not collapse a long discharge estimate", () => {
	const rig = new Rig(new Estimator(), 4000);
	const before = rig.run({ seconds: 1800, ongridW: 0, offgridW: 300 }).toEmptyH ?? 0;
	const during = rig.run({ seconds: 45, ongridW: 0, offgridW: 2000 }).toEmptyH ?? 0;
	expect(before).toBeGreaterThan(9);
	expect(during).toBeGreaterThan(before * 0.7);
});

test("a sustained load change is adopted within 30 minutes", () => {
	const rig = new Rig(new Estimator(), 4000);
	const got = rig.run({ seconds: 1800, ongridW: 0, offgridW: 300 }, { seconds: 1800, ongridW: 0, offgridW: 1500 });
	const truth = (rig.capacityWh - 0.12 * RATED) / 1.09 / 1500;
	expect(got.toEmptyH).toBeGreaterThan(truth * 0.95);
	expect(got.toEmptyH).toBeLessThan(truth * 1.15);
});

test("at the floor the runtime is zero", () => {
	const rig = new Rig(new Estimator(), 0.12 * RATED);
	expect(rig.run({ seconds: 60, ongridW: 0, offgridW: 300 }).toEmptyH).toBe(0);
});

test("a mode change needs two samples in a row and then warms up", () => {
	const rig = new Rig(new Estimator(), 4000);
	rig.run({ seconds: 60, ongridW: -797 });
	expect(rig.run({ seconds: 15, ongridW: 0, offgridW: 300 }).mode).toBe("charging");
	const switched = rig.run({ seconds: 15, ongridW: 0, offgridW: 300 });
	expect(switched.mode).toBe("discharging");
	expect(switched.warmingUp).toBe(true);
	expect(rig.run({ seconds: 60, ongridW: 0, offgridW: 300 }).warmingUp).toBe(false);
});

test("a gap longer than two minutes restarts the warm-up", () => {
	const rig = new Rig(new Estimator(), 4000);
	rig.run({ seconds: 300, ongridW: 0, offgridW: 300 });
	rig.t += 600;
	expect(rig.run({ seconds: 15, ongridW: 0, offgridW: 300 }).warmingUp).toBe(true);
});

test("on grid the runtime is a projection from the backup load", () => {
	const rig = new Rig(new Estimator(), 4000);
	const got = rig.run({ seconds: 60, ongridW: -400, offgridW: 400 });
	expect(got.mode).toBe("idle");
	expect(got.projected).toBe(true);
	expect(got.toEmptyH).toBeCloseTo((4000 - 0.12 * RATED) / 1.09 / 400, 1);
});

test("on grid with an idle backup socket the projection uses the typical load", () => {
	const none = new Rig(new Estimator(), 4000).run({ seconds: 60, ongridW: -797 });
	expect(none.toEmptyH).toBeNull();
	const known = new Rig(new Estimator(learned({ typicalLoadW: 400 })), 4000).run({ seconds: 15, ongridW: -797 });
	expect(known.projected).toBe(true);
	expect(known.toEmptyH).toBeCloseTo((4000 - 0.12 * RATED) / 1.09 / 400, 1);
});

test("the charge ratio is learned from the capacity counter", () => {
	const est = new Estimator();
	new Rig(est, 2000, 0.8).run({ seconds: 3600, ongridW: -800 });
	expect(est.learned.chargeRatio).toBeLessThan(0.84);
	expect(est.learned.chargeRatio).toBeGreaterThan(0.8);
});

test("the discharge ratio is learned from the capacity counter", () => {
	const est = new Estimator();
	new Rig(est, 4500, 0.88, 1.2).run({ seconds: 3600, ongridW: 0, offgridW: 800 });
	expect(est.learned.dischargeRatio).toBeGreaterThan(1.13);
	expect(est.learned.dischargeRatio).toBeLessThan(1.2);
});

test("a power drop above 90 percent is learned as taper", () => {
	const est = new Estimator();
	const rig = new Rig(est, RATED * 0.895);
	rig.run({ seconds: 120, ongridW: -800 });
	rig.capacityWh = RATED * 0.925;
	rig.run({ seconds: 300, ongridW: -400 });
	expect(est.learned.taper[2]).toBeLessThan(0.9);
	expect(est.learned.taper[0]).toBe(1);
});

test("a discharge leaves a typical load behind", () => {
	const est = new Estimator();
	new Rig(est, 4000).run({ seconds: 600, ongridW: 0, offgridW: 350 });
	expect(est.learned.typicalLoadW).toBeCloseTo(350, 0);
});

test("the floor is configurable", () => {
	const est = new Estimator(defaultLearned(), 20);
	const got = new Rig(est, 4000).run({ seconds: 600, ongridW: 0, offgridW: 300 });
	expect(got.toEmptyH).toBeCloseTo((rigUsable(4000, 600, 300) - 0.2 * RATED) / 1.09 / 300, 1);
});

function rigUsable(startWh: number, seconds: number, loadW: number): number {
	return startWh - (loadW * 1.09 * (seconds - STEP_S)) / 3600;
}
```

- [ ] **3.2 Run `npm test`.** Expected: FAIL, cannot resolve `./estimator`.

- [ ] **3.3 Write `estimator.ts`:**

```ts
import type { BatStatus, EsStatus, Estimate, Learned, Mode } from "./types";

const IDLE_W = 30;
const GAP_S = 120;
const WARMUP_S = 40;
const TAU_FAST_S = 60;
const TAU_MID_S = 900;
const TAU_CHARGE_S = 120;
const TAU_TYPICAL_S = 6 * 3600;
const TAU_DECAY_H = 1 / 6;
const TAPER_FROM_PCT = 90;
const TAPER_GAIN = 0.05;
const CAL_MIN_AC_WH = 150;
const CAL_GAIN = 0.2;
const MAX_H = 240;

export function defaultLearned(): Learned {
	return { chargeRatio: 0.88, dischargeRatio: 1.09, typicalLoadW: null, taper: new Array<number>(10).fill(1) };
}

export function solveRuntime(acWh: number, nowW: number, baseW: number): number {
	const used = (hours: number) => baseW * hours + (nowW - baseW) * TAU_DECAY_H * (1 - Math.exp(-hours / TAU_DECAY_H));
	if (acWh <= 0) return 0;
	if (used(MAX_H) <= acWh) return MAX_H;

	let low = 0;
	let high = MAX_H;
	for (let i = 0; i < 60; i++) {
		const mid = (low + high) / 2;
		if (used(mid) < acWh) low = mid;
		else high = mid;
	}
	return high;
}

export class Estimator {
	floorPct: number;
	#learned: Learned;
	#bat?: BatStatus;
	#lastT?: number;
	#mode: Mode = "idle";
	#pending?: Mode;
	#modeSince = 0;
	#recent: number[] = [];
	#fastW?: number;
	#midW?: number;
	#backupW?: number;
	#chargeW?: number;
	#refChargeW?: number;
	#cal?: { capacityWh: number; acWh: number };

	constructor(learned: Learned = defaultLearned(), floorPct = 12) {
		this.#learned = copy(learned);
		this.floorPct = floorPct;
	}

	get learned(): Learned {
		return copy(this.#learned);
	}

	restore(learned: Learned): void {
		this.#learned = copy(learned);
	}

	battery(bat: BatStatus): void {
		this.#bat = bat;
		if (this.#mode === "idle") return;
		if (this.#cal === undefined) {
			this.#cal = { capacityWh: bat.capacityWh, acWh: 0 };
			return;
		}

		const gained = bat.capacityWh - this.#cal.capacityWh;
		const moved = this.#mode === "charging" ? gained : -gained;
		if (this.#cal.acWh < CAL_MIN_AC_WH || moved <= 0) return;

		const ratio = moved / this.#cal.acWh;
		if (this.#mode === "charging") {
			this.#learned.chargeRatio += CAL_GAIN * (clamp(ratio, 0.7, 1) - this.#learned.chargeRatio);
		} else {
			this.#learned.dischargeRatio += CAL_GAIN * (clamp(ratio, 1, 1.5) - this.#learned.dischargeRatio);
		}
		this.#cal = { capacityWh: bat.capacityWh, acWh: 0 };
	}

	sample(es: EsStatus): Estimate {
		const acW = es.ongridW + es.offgridW;
		const elapsed = this.#lastT === undefined ? Infinity : (es.t - this.#lastT) / 1000;
		const continuous = elapsed > 0 && elapsed <= GAP_S;
		const dt = continuous ? elapsed : 0;
		this.#lastT = es.t;

		const target: Mode = acW > IDLE_W ? "discharging" : acW < -IDLE_W ? "charging" : "idle";
		if (!continuous) {
			this.#enter(target, es.t);
			this.#backupW = undefined;
		} else if (target === this.#mode) {
			this.#pending = undefined;
		} else if (target === this.#pending) {
			this.#enter(target, es.t);
		} else {
			this.#pending = target;
		}

		this.#backupW = ema(this.#backupW, es.offgridW, dt, TAU_MID_S);
		if (target === this.#mode) this.#track(acW, Math.floor(es.socPct), dt);

		return {
			mode: this.#mode,
			socPct: es.socPct,
			batteryAcW: acW,
			toFullH: this.#toFull(),
			...this.#toEmpty(),
			warmingUp: this.#mode !== "idle" && (es.t - this.#modeSince) / 1000 < WARMUP_S,
		};
	}

	#enter(mode: Mode, t: number): void {
		this.#mode = mode;
		this.#pending = undefined;
		this.#modeSince = t;
		this.#recent = [];
		this.#fastW = undefined;
		this.#midW = undefined;
		this.#chargeW = undefined;
		this.#refChargeW = undefined;
		this.#cal = undefined;
	}

	#track(acW: number, socPct: number, dt: number): void {
		if (this.#mode === "idle") return;
		if (this.#cal !== undefined) this.#cal.acWh += (Math.abs(acW) * dt) / 3600;

		if (this.#mode === "charging") {
			const chargeW = ema(this.#chargeW, -acW, dt, TAU_CHARGE_S);
			this.#chargeW = chargeW;
			if (socPct < TAPER_FROM_PCT) {
				this.#refChargeW = chargeW;
			} else if (this.#refChargeW !== undefined) {
				const i = Math.min(9, socPct - TAPER_FROM_PCT);
				const seen = clamp(chargeW / this.#refChargeW, 0.05, 1);
				this.#learned.taper[i] += TAPER_GAIN * (seen - this.#learned.taper[i]);
			}
			return;
		}

		this.#recent = [...this.#recent, acW].slice(-3);
		const load = median(this.#recent);
		this.#fastW = ema(this.#fastW, load, dt, TAU_FAST_S);
		this.#midW = ema(this.#midW, load, dt, TAU_MID_S);
		this.#learned.typicalLoadW = ema(this.#learned.typicalLoadW ?? undefined, load, dt, TAU_TYPICAL_S);
	}

	#toFull(): number | null {
		const bat = this.#bat;
		const chargeW = this.#chargeW;
		if (this.#mode !== "charging" || bat === undefined || chargeW === undefined || chargeW <= 0) return null;

		const bucketWh = bat.ratedWh / 100;
		const pctNow = Math.min(99, Math.floor(bat.capacityWh / bucketWh));
		const baseW = (chargeW / this.#taperAt(pctNow)) * this.#learned.chargeRatio;

		let hours = 0;
		for (let pct = pctNow; pct < 100; pct++) {
			const from = Math.max(bat.capacityWh, pct * bucketWh);
			hours += Math.max(0, (pct + 1) * bucketWh - from) / (baseW * this.#taperAt(pct));
		}
		return Math.min(hours, MAX_H);
	}

	#toEmpty(): Pick<Estimate, "toEmptyH" | "projected"> {
		const bat = this.#bat;
		const projected = this.#mode !== "discharging";
		if (bat === undefined) return { toEmptyH: null, projected };

		const acWh = Math.max(0, bat.capacityWh - (this.floorPct / 100) * bat.ratedWh) / this.#learned.dischargeRatio;
		if (!projected) {
			if (this.#fastW === undefined || this.#midW === undefined) return { toEmptyH: null, projected };
			return { toEmptyH: solveRuntime(acWh, this.#fastW, this.#midW), projected };
		}

		const backupW = this.#backupW ?? 0;
		const loadW = backupW > IDLE_W ? backupW : this.#learned.typicalLoadW;
		if (loadW === null || loadW <= 0) return { toEmptyH: null, projected };
		return { toEmptyH: Math.min(MAX_H, acWh / loadW), projected };
	}

	#taperAt(pct: number): number {
		return pct < TAPER_FROM_PCT ? 1 : this.#learned.taper[pct - TAPER_FROM_PCT];
	}
}

function ema(prev: number | undefined, value: number, dt: number, tau: number): number {
	return prev === undefined ? value : prev + (1 - Math.exp(-dt / tau)) * (value - prev);
}

function median(values: number[]): number {
	const sorted = [...values].sort((a, b) => a - b);
	return sorted[Math.floor(sorted.length / 2)];
}

function clamp(value: number, low: number, high: number): number {
	return Math.min(high, Math.max(low, value));
}

function copy(learned: Learned): Learned {
	return { ...learned, taper: [...learned.taper] };
}
```

- [ ] **3.4 Run `npm test && npm run typecheck`.** Expected: 33 passed. If a learning test misses its bounds by a few percent, fix the estimator only when its arithmetic is wrong; the bounds come from the constants above (`CAL_GAIN` 0.2 with one update per 150 AC Wh; `TAPER_GAIN` 0.05 per sample).

- [ ] **3.5 Commit:** `git add -A && git commit -m "feat: add battery eta estimator with learned ratios and taper"`

---

## Task 4: Duration format, key views, SVG

**Files**
- Create: `streamdeck/src/core/format.ts`, `views.ts`, `render.ts`
- Test: `streamdeck/src/core/format.test.ts`, `views.test.ts`

**Consumes:** `Estimate`; `DeviceErrorKind` from `client.ts`.

**Produces**
- `format.ts`: `formatDuration(hours): string`, `class Stabiliser { next(hours: number | null): number | null }`
- `views.ts`: `PollError`, `Snapshot`, `Tone`, `KeyView`, `levelView(s)`, `etaHours(estimate)`, `etaView(s, hours)`
- `render.ts`: `renderKey(view): string`, `toDataUri(markup): string`

- [ ] **4.1 Write the failing `format.test.ts`:**

```ts
import { expect, test } from "vitest";

import { formatDuration, Stabiliser } from "./format";

test.each([
	[30, ">24h"],
	[12.4, "12h"],
	[3.66, "3h40"],
	[1, "1h00"],
	[0.74, "45m"],
	[0.1, "6m"],
	[0, "0m"],
])("formats %f h as %s", (hours, text) => {
	expect(formatDuration(hours)).toBe(text);
});

test("the stabiliser holds a value until it moves most of a display step", () => {
	const stable = new Stabiliser();
	expect(stable.next(3.0)).toBe(3.0);
	expect(stable.next(3.05)).toBe(3.0);
	expect(stable.next(2.95)).toBe(3.0);
	expect(stable.next(2.8)).toBe(2.8);
});

test("the stabiliser forgets when there is no estimate", () => {
	const stable = new Stabiliser();
	stable.next(3.0);
	expect(stable.next(null)).toBeNull();
	expect(stable.next(5.0)).toBe(5.0);
});
```

- [ ] **4.2 Run `npm test`.** Expected: FAIL, cannot resolve `./format`.

- [ ] **4.3 Write `format.ts`:**

```ts
export function formatDuration(hours: number): string {
	const minutes = hours * 60;
	if (minutes >= 24 * 60) return ">24h";
	if (minutes >= 600) return `${Math.round(minutes / 60)}h`;
	if (minutes >= 60) {
		const rounded = Math.round(minutes / 10) * 10;
		return `${Math.floor(rounded / 60)}h${String(rounded % 60).padStart(2, "0")}`;
	}
	if (minutes >= 10) return `${Math.round(minutes / 5) * 5}m`;
	return `${Math.max(0, Math.round(minutes))}m`;
}

export class Stabiliser {
	#shown: number | null = null;

	next(hours: number | null): number | null {
		if (hours === null || this.#shown === null || Math.abs(hours - this.#shown) >= 0.75 * stepHours(hours)) {
			this.#shown = hours;
		}
		return this.#shown;
	}
}

function stepHours(hours: number): number {
	const minutes = hours * 60;
	return (minutes >= 600 ? 60 : minutes >= 60 ? 10 : minutes >= 10 ? 5 : 1) / 60;
}
```

- [ ] **4.4 Write the failing `views.test.ts`:**

```ts
import { expect, test } from "vitest";

import { renderKey } from "./render";
import type { Estimate } from "./types";
import { etaHours, etaView, levelView } from "./views";

const charging: Estimate = {
	mode: "charging",
	socPct: 82,
	batteryAcW: -797,
	toFullH: 1.25,
	toEmptyH: 9.5,
	projected: true,
	warmingUp: false,
};
const discharging: Estimate = { ...charging, mode: "discharging", batteryAcW: 300, toFullH: null, toEmptyH: 3.66, projected: false };
const idle: Estimate = { ...charging, mode: "idle", socPct: 100, batteryAcW: 0, toFullH: null, toEmptyH: 11.2 };

test("level shows percent, signed power and a fill", () => {
	expect(levelView({ estimate: charging })).toMatchObject({ value: "82%", foot: "+797W", tone: "good", fill: 0.82, stale: false });
	expect(levelView({ estimate: discharging })).toMatchObject({ foot: "-300W", tone: "warn" });
	expect(levelView({ estimate: { ...discharging, socPct: 15 } }).tone).toBe("bad");
	expect(levelView({ estimate: idle }).foot).toBe("IDLE");
});

test("before the first reading the keys show a placeholder", () => {
	expect(levelView({}).value).toBe("··");
	expect(etaView({}, null).value).toBe("··");
});

test("errors without a reading name the cause", () => {
	expect(levelView({ error: "blocked" }).value).toBe("LAN");
	expect(etaView({ error: "settings" }, null).value).toBe("SET IP");
	expect(levelView({ error: "timeout" }).value).toBe("NO LINK");
});

test("errors with a reading keep the value and mark it stale", () => {
	expect(levelView({ estimate: charging, error: "timeout" })).toMatchObject({ value: "82%", stale: true });
});

test("the eta key follows the time to full while charging and the time to empty otherwise", () => {
	expect(etaHours(charging)).toBe(1.25);
	expect(etaHours(discharging)).toBe(3.66);
	expect(etaHours(idle)).toBe(11.2);
	expect(etaHours(undefined)).toBeNull();
});

test("eta while charging", () => {
	expect(etaView({ estimate: charging }, 1.25)).toMatchObject({ label: "FULL IN", value: "1h20", foot: "797W", tone: "good" });
	expect(etaView({ estimate: { ...charging, warmingUp: true } }, 1.25).value).toBe("··");
	expect(etaView({ estimate: charging }, 0).value).toBe("0m");
});

test("eta while discharging", () => {
	expect(etaView({ estimate: discharging }, 3.66)).toMatchObject({ label: "EMPTY IN", value: "3h40", foot: "300W", tone: "warn" });
	expect(etaView({ estimate: discharging }, 0.3).tone).toBe("bad");
	expect(etaView({ estimate: discharging }, 0).value).toBe("0m");
	expect(etaView({ estimate: discharging }, null).value).toBe("··");
});

test("eta while idle is a projection, or the full mark when there is none", () => {
	expect(etaView({ estimate: idle }, 11.2)).toMatchObject({ label: "IF OUTAGE", value: "11h", tone: "neutral" });
	expect(etaView({ estimate: idle }, null)).toMatchObject({ label: "ETA", value: "FULL", tone: "good" });
	expect(etaView({ estimate: { ...idle, socPct: 60 } }, null).value).toBe("—");
});

test("rendered keys never contain NaN or Infinity and escape markup", () => {
	const svg = renderKey(etaView({ estimate: idle }, 30));
	expect(svg).toContain("&gt;24h");
	expect(svg).not.toMatch(/NaN|Infinity/);
});

test("a stale key is drawn without the accent colours", () => {
	const svg = renderKey(levelView({ estimate: charging, error: "timeout" }));
	expect(svg).not.toContain("#4ADE80");
});
```

- [ ] **4.5 Run `npm test`.** Expected: FAIL, cannot resolve `./render` and `./views`.

- [ ] **4.6 Write `views.ts`:**

```ts
import type { DeviceErrorKind } from "./client";
import { formatDuration } from "./format";
import type { Estimate } from "./types";

export type PollError = DeviceErrorKind | "settings";

export type Snapshot = { estimate?: Estimate; tempC?: number; error?: PollError; message?: string };

export type Tone = "neutral" | "good" | "warn" | "bad";

export type KeyView = { label: string; value: string; foot: string; tone: Tone; stale: boolean; fill?: number };

const ERROR_TEXT: Record<PollError, string> = {
	blocked: "LAN",
	settings: "SET IP",
	timeout: "NO LINK",
	network: "NO LINK",
	protocol: "ERROR",
};

export function levelView(s: Snapshot): KeyView {
	const est = s.estimate;
	if (est === undefined) return blank("BATTERY", s);

	const watts = Math.round(Math.abs(est.batteryAcW));
	const foot = est.mode === "charging" ? `+${watts}W` : est.mode === "discharging" ? `-${watts}W` : "IDLE";
	const tone: Tone =
		est.mode === "charging" ? "good" : est.mode === "idle" ? "neutral" : est.socPct < 20 ? "bad" : "warn";
	return { label: "BATTERY", value: `${est.socPct}%`, foot, tone, stale: s.error !== undefined, fill: est.socPct / 100 };
}

export function etaHours(est: Estimate | undefined): number | null {
	if (est === undefined) return null;
	return est.mode === "charging" ? est.toFullH : est.toEmptyH;
}

export function etaView(s: Snapshot, hours: number | null): KeyView {
	const est = s.estimate;
	if (est === undefined) return blank("ETA", s);

	const stale = s.error !== undefined;
	const foot = `${Math.round(Math.abs(est.batteryAcW))}W`;
	const value = est.warmingUp || hours === null ? "··" : formatDuration(hours);

	if (est.mode === "charging") return { label: "FULL IN", value, foot, tone: "good", stale };
	if (est.mode === "discharging") {
		return { label: "EMPTY IN", value, foot, tone: hours !== null && hours < 0.5 ? "bad" : "warn", stale };
	}
	if (hours !== null) return { label: "IF OUTAGE", value: formatDuration(hours), foot: "", tone: "neutral", stale };

	const full = est.socPct >= 100;
	return { label: "ETA", value: full ? "FULL" : "—", foot: "", tone: full ? "good" : "neutral", stale };
}

function blank(label: string, s: Snapshot): KeyView {
	return { label, value: s.error === undefined ? "··" : ERROR_TEXT[s.error], foot: "", tone: "neutral", stale: true };
}
```

- [ ] **4.7 Write `render.ts`.** Colours and layout follow `streamdeck-ipscut-visitors/src/render.ts`:

```ts
import type { KeyView } from "./views";

const SIZE = 144;
const FONT = "'Helvetica Neue', Helvetica, Arial, sans-serif";

const COLOR = {
	bg: "#17171A",
	track: "#2A2A30",
	label: "#8A8A93",
	value: "#FFFFFF",
	neutral: "#8A8A93",
	good: "#4ADE80",
	warn: "#FBBF24",
	bad: "#F87171",
	stale: "#5A5A61",
} as const;

export function renderKey(view: KeyView): string {
	const ink = view.stale ? COLOR.stale : COLOR.value;
	const accent = view.stale ? COLOR.stale : COLOR[view.tone];
	const size = view.value.length <= 3 ? 52 : view.value.length === 4 ? 42 : view.value.length === 5 ? 36 : 26;

	const bar =
		view.fill === undefined
			? ""
			: `<rect x="20" y="130" width="104" height="6" rx="3" fill="${COLOR.track}" />` +
				`<rect x="20" y="130" width="${(104 * Math.min(1, Math.max(0, view.fill))).toFixed(1)}" height="6" rx="3" fill="${accent}" />`;

	return (
		`<svg xmlns="http://www.w3.org/2000/svg" width="${SIZE}" height="${SIZE}" viewBox="0 0 ${SIZE} ${SIZE}">` +
		`<rect width="${SIZE}" height="${SIZE}" rx="18" fill="${COLOR.bg}" />` +
		text(view.label, 32, 13, 600, view.stale ? COLOR.stale : COLOR.label, 1.6) +
		text(view.value, 84, size, 700, ink, 0) +
		text(view.foot, 116, 20, 600, accent, 0) +
		bar +
		(view.stale ? `<circle cx="126" cy="20" r="5" fill="${COLOR.bad}" />` : "") +
		`</svg>`
	);
}

export function toDataUri(markup: string): string {
	return `data:image/svg+xml;charset=utf8,${encodeURIComponent(markup)}`;
}

function text(content: string, y: number, size: number, weight: number, fill: string, spacing: number): string {
	if (content === "") return "";
	return (
		`<text x="72" y="${y}" text-anchor="middle" font-family="${FONT}" font-size="${size}" ` +
		`font-weight="${weight}" letter-spacing="${spacing}" fill="${fill}">${escapeXml(content)}</text>`
	);
}

function escapeXml(content: string): string {
	return content.replace(/[<>&]/g, (char) => (char === "<" ? "&lt;" : char === ">" ? "&gt;" : "&amp;"));
}
```

A stale key still paints the red dot, so the last test asserts only that the green accent is gone.

- [ ] **4.8 Run `npm test && npm run typecheck`.** Expected: 52 passed.

- [ ] **4.9 Commit:** `git add -A && git commit -m "feat: add duration format, key views and svg rendering"`

---

## Task 5: Settings and poller

**Files**
- Create: `streamdeck/src/core/settings.ts`, `poller.ts`, `streamdeck/src/probe.ts`
- Test: `streamdeck/src/core/settings.test.ts`, `poller.test.ts`

**Consumes:** `Device`, `DeviceError`, `MarstekClient`; `ProtocolError`, `toEsStatus`, `toBatStatus`; `Estimator`, `defaultLearned`; `Snapshot`.

**Produces**
- `settings.ts`: `Settings`, `Resolved`, `SettingsError`, `resolve(settings): Resolved`, `restoreLearned(settings): Learned`
- `poller.ts`: `PollerDeps`, `class Poller` with `snapshot`, `start()`, `kick(): Promise<void>`, `reconfigure()`, `stop()`

- [ ] **5.1 Write the failing `settings.test.ts`:**

```ts
import { expect, test } from "vitest";

import { defaultLearned } from "./estimator";
import { resolve, restoreLearned, SettingsError } from "./settings";

test("fills the port and floor defaults", () => {
	expect(resolve({ host: " 192.168.68.50 " })).toEqual({ host: "192.168.68.50", port: 30000, floorPct: 12 });
});

test("accepts numbers typed into text fields", () => {
	expect(resolve({ host: "battery.lan", port: "30001", floorPercent: "20" })).toEqual({ host: "battery.lan", port: 30001, floorPct: 20 });
});

test.each([
	[{}, /battery IP/],
	[{ host: "192.168.68.50; rm" }, /battery IP/],
	[{ host: "a", port: "70000" }, /Port/],
	[{ host: "a", port: "abc" }, /Port/],
	[{ host: "a", floorPercent: "90" }, /Reserve/],
])("rejects %j", (settings, message) => {
	expect(() => resolve(settings)).toThrow(SettingsError);
	expect(() => resolve(settings)).toThrow(message);
});

test("restores learned values that are in range", () => {
	const learned = { chargeRatio: 0.9, dischargeRatio: 1.1, typicalLoadW: 350, taper: [1, 1, 1, 1, 1, 0.8, 0.6, 0.5, 0.4, 0.3] };
	expect(restoreLearned({ learned })).toEqual(learned);
});

test("falls back to defaults when learned values are damaged", () => {
	expect(restoreLearned({})).toEqual(defaultLearned());
	expect(restoreLearned({ learned: { ...defaultLearned(), taper: [1, 2] } })).toEqual(defaultLearned());
	expect(restoreLearned({ learned: { ...defaultLearned(), chargeRatio: 5 } })).toEqual(defaultLearned());
});
```

- [ ] **5.2 Run `npm test`.** Expected: FAIL, cannot resolve `./settings`.

- [ ] **5.3 Write `settings.ts`:**

```ts
import { defaultLearned } from "./estimator";
import type { Learned } from "./types";

export type Settings = {
	host?: string;
	port?: string | number;
	floorPercent?: string | number;
	learned?: Learned;
};

export type Resolved = { host: string; port: number; floorPct: number };

export class SettingsError extends Error {}

const HOST = /^[A-Za-z0-9.-]+$/;

export function resolve(settings: Settings): Resolved {
	const host = settings.host?.trim() ?? "";
	if (!HOST.test(host)) throw new SettingsError("Set the battery IP in the key settings");

	const port = Number(settings.port ?? 30000);
	if (!Number.isInteger(port) || port < 1 || port > 65535) throw new SettingsError("Port must be 1 to 65535");

	const floorPct = Number(settings.floorPercent ?? 12);
	if (!Number.isFinite(floorPct) || floorPct < 0 || floorPct > 50) throw new SettingsError("Reserve must be 0 to 50 percent");

	return { host, port, floorPct };
}

export function restoreLearned(settings: Settings): Learned {
	const learned = settings.learned;
	if (learned === undefined) return defaultLearned();

	const taperOk =
		Array.isArray(learned.taper) && learned.taper.length === 10 && learned.taper.every((value) => inRange(value, 0.05, 1));
	const typicalOk = learned.typicalLoadW === null || inRange(learned.typicalLoadW, 0, 10_000);
	const ok = taperOk && typicalOk && inRange(learned.chargeRatio, 0.7, 1) && inRange(learned.dischargeRatio, 1, 1.5);

	return ok ? { ...learned, taper: [...learned.taper] } : defaultLearned();
}

function inRange(value: number, low: number, high: number): boolean {
	return typeof value === "number" && Number.isFinite(value) && value >= low && value <= high;
}
```

- [ ] **5.4 Write the failing `poller.test.ts`:**

```ts
import { afterEach, beforeEach, expect, test, vi } from "vitest";

import { type Device, DeviceError } from "./client";
import { Estimator } from "./estimator";
import { Poller } from "./poller";
import type { JsonObject } from "./protocol";
import { SettingsError } from "./settings";
import type { Snapshot } from "./views";

const ES: JsonObject = { bat_soc: 82, ongrid_power: -797, offgrid_power: 0 };
const BAT: JsonObject = { bat_capacity: 4244, rated_capacity: 5120, bat_temp: 24 };

class FakeDevice implements Device {
	calls: string[] = [];
	fail?: Error;
	closed = false;
	call(method: string): Promise<JsonObject> {
		this.calls.push(method);
		if (this.fail !== undefined) return Promise.reject(this.fail);
		return Promise.resolve(method === "ES.GetStatus" ? ES : BAT);
	}
	close(): void {
		this.closed = true;
	}
}

function rig(connect?: () => Promise<{ device: Device; floorPct: number }>) {
	const device = new FakeDevice();
	const published: Snapshot[] = [];
	const poller = new Poller({
		connect: connect ?? (() => Promise.resolve({ device, floorPct: 12 })),
		now: () => Date.now(),
		publish: (snapshot) => published.push(snapshot),
		estimator: new Estimator(),
	});
	return { device, published, poller };
}

beforeEach(() => vi.useFakeTimers());
afterEach(() => vi.useRealTimers());

test("the first poll reads the battery and publishes an estimate", async () => {
	const { device, published, poller } = rig();
	await poller.kick();
	expect(device.calls).toEqual(["Bat.GetStatus", "ES.GetStatus"]);
	expect(published.at(-1)?.estimate?.socPct).toBe(82);
	expect(published.at(-1)?.tempC).toBe(24);
	poller.stop();
});

test("polls every 15 s and reads the capacity every second poll", async () => {
	const { device, poller } = rig();
	await poller.kick();
	await vi.advanceTimersByTimeAsync(15_000);
	await vi.advanceTimersByTimeAsync(15_000);
	expect(device.calls).toEqual(["Bat.GetStatus", "ES.GetStatus", "ES.GetStatus", "Bat.GetStatus", "ES.GetStatus"]);
	poller.stop();
});

test("two failed polls keep the last reading; the third marks it stale and slows down", async () => {
	const { device, published, poller } = rig();
	await poller.kick();
	device.fail = new DeviceError("timeout", "No reply");

	await vi.advanceTimersByTimeAsync(15_000);
	await vi.advanceTimersByTimeAsync(15_000);
	expect(published.at(-1)?.error).toBeUndefined();

	await vi.advanceTimersByTimeAsync(15_000);
	expect(published.at(-1)).toMatchObject({ error: "timeout", estimate: { socPct: 82 } });

	const before = device.calls.length;
	await vi.advanceTimersByTimeAsync(45_000);
	expect(device.calls.length).toBe(before);
	await vi.advanceTimersByTimeAsync(15_000);
	expect(device.calls.length).toBeGreaterThan(before);
	poller.stop();
});

test("the device coming back clears the error on the next poll", async () => {
	const { device, published, poller } = rig();
	device.fail = new DeviceError("timeout", "No reply");
	await poller.kick();
	await poller.kick();
	await poller.kick();
	expect(published.at(-1)?.error).toBe("timeout");

	device.fail = undefined;
	await poller.kick();
	expect(published.at(-1)?.error).toBeUndefined();
	expect(published.at(-1)?.estimate?.socPct).toBe(82);
	poller.stop();
});

test("a blocked network shows on the first failure", async () => {
	const { device, published, poller } = rig();
	device.fail = new DeviceError("blocked", "send EHOSTUNREACH");
	await poller.kick();
	expect(published.at(-1)?.error).toBe("blocked");
	poller.stop();
});

test("bad settings show at once and reconfigure reconnects", async () => {
	const device = new FakeDevice();
	let bad = true;
	const { published, poller } = rig(() =>
		bad ? Promise.reject(new SettingsError("Set the battery IP in the key settings")) : Promise.resolve({ device, floorPct: 20 }),
	);
	await poller.kick();
	expect(published.at(-1)).toMatchObject({ error: "settings", message: "Set the battery IP in the key settings" });

	bad = false;
	poller.reconfigure();
	await poller.kick();
	expect(published.at(-1)?.estimate?.socPct).toBe(82);
	poller.stop();
});

test("overlapping kicks share one poll", async () => {
	const { device, poller } = rig();
	await Promise.all([poller.kick(), poller.kick()]);
	expect(device.calls).toEqual(["Bat.GetStatus", "ES.GetStatus"]);
	poller.stop();
});
```

- [ ] **5.5 Run `npm test`.** Expected: FAIL, cannot resolve `./poller`.

- [ ] **5.6 Write `poller.ts`:**

```ts
import { type Device, DeviceError } from "./client";
import type { Estimator } from "./estimator";
import { toBatStatus, toEsStatus } from "./protocol";
import { SettingsError } from "./settings";
import type { PollError, Snapshot } from "./views";

const TICK_MS = 15_000;
const BACKOFF_MS = 60_000;
const BAT_EVERY = 2;
const FAILS_BEFORE_ERROR = 3;

export type PollerDeps = {
	connect(): Promise<{ device: Device; floorPct: number }>;
	now(): number;
	publish(snapshot: Snapshot): void;
	estimator: Estimator;
};

export class Poller {
	#device?: Device;
	#timer?: NodeJS.Timeout;
	#running?: Promise<void>;
	#stopped = false;
	#ticks = 0;
	#fails = 0;
	#tempC?: number;
	#last: Snapshot = {};

	constructor(private readonly deps: PollerDeps) {}

	get snapshot(): Snapshot {
		return this.#last;
	}

	start(): void {
		this.#stopped = false;
		void this.kick();
	}

	stop(): void {
		this.#stopped = true;
		clearTimeout(this.#timer);
		this.#device?.close();
		this.#device = undefined;
	}

	reconfigure(): void {
		this.#device?.close();
		this.#device = undefined;
		this.#fails = 0;
		this.#stopped = false;
		void this.kick();
	}

	async kick(): Promise<void> {
		if (this.#running !== undefined) return this.#running;

		clearTimeout(this.#timer);
		this.#running = this.#tick();
		try {
			await this.#running;
		} finally {
			this.#running = undefined;
			if (!this.#stopped) {
				const delay = this.#fails >= FAILS_BEFORE_ERROR ? BACKOFF_MS : TICK_MS;
				this.#timer = setTimeout(() => void this.kick(), delay);
			}
		}
	}

	async #tick(): Promise<void> {
		try {
			if (this.#device === undefined) {
				const { device, floorPct } = await this.deps.connect();
				this.#device = device;
				this.deps.estimator.floorPct = floorPct;
			}
			const device = this.#device;

			if (this.#ticks++ % BAT_EVERY === 0) {
				const bat = toBatStatus(await device.call("Bat.GetStatus"), this.deps.now());
				this.deps.estimator.battery(bat);
				this.#tempC = bat.tempC;
			}
			const es = toEsStatus(await device.call("ES.GetStatus"), this.deps.now());

			this.#fails = 0;
			this.#set({ estimate: this.deps.estimator.sample(es), tempC: this.#tempC });
		} catch (err) {
			this.#fails++;
			const error: PollError =
				err instanceof DeviceError ? err.kind : err instanceof SettingsError ? "settings" : "protocol";
			const urgent = error === "settings" || error === "blocked";
			if (urgent || this.#fails >= FAILS_BEFORE_ERROR) {
				this.#set({ ...this.#last, error, message: err instanceof Error ? err.message : "Unknown error" });
			}
		}
	}

	#set(snapshot: Snapshot): void {
		this.#last = snapshot;
		this.deps.publish(snapshot);
	}
}
```

- [ ] **5.7 Run `npm test && npm run typecheck`.** Expected: 68 passed.

- [ ] **5.8 Write `src/probe.ts`**, a terminal check of the whole core against the real battery:

```ts
import { MarstekClient } from "./core/client";
import { Estimator } from "./core/estimator";
import { formatDuration } from "./core/format";
import { Poller } from "./core/poller";
import { resolve } from "./core/settings";

const settings = resolve({ host: process.env.MARSTEK_HOST, port: process.env.MARSTEK_PORT });
const estimator = new Estimator();

const show = (hours: number | null) => (hours === null ? "—" : formatDuration(hours));

const poller = new Poller({
	connect: () => Promise.resolve({ device: new MarstekClient(settings.host, settings.port), floorPct: settings.floorPct }),
	now: () => Date.now(),
	estimator,
	publish: ({ estimate, tempC, error, message }) => {
		const time = new Date().toISOString().slice(11, 19);
		if (estimate === undefined) return console.log(time, error ?? "waiting", message ?? "");
		console.log(
			time,
			`${estimate.socPct}%`,
			`${Math.round(estimate.batteryAcW)}W`,
			estimate.mode,
			`full ${show(estimate.toFullH)}`,
			`${estimate.projected ? "if-outage" : "empty"} ${show(estimate.toEmptyH)}`,
			`${tempC ?? "?"}C`,
			error ?? "",
			JSON.stringify(estimator.learned),
		);
	},
});

poller.start();
```

- [ ] **5.9 Gate on the real device:** `MARSTEK_HOST=192.168.68.50 npm run probe`, leave it 2 minutes. Expected: a line every 15 s with the same percent and watts the Marstek app shows. While charging, `full` is within 10 % of `(5120 − remaining Wh) ÷ (watts × 0.88)`. Stop with Ctrl-C.

- [ ] **5.10 Commit:** `git add -A && git commit -m "feat: add settings, poller and terminal probe"`

---

## Task 6: Stream Deck layer

**Files**
- Create: `streamdeck/src/actions/keys.ts`, `streamdeck/com.mlapin.marstek.sdPlugin/ui/settings.html`
- Replace: `streamdeck/src/plugin.ts` (the Task 1 skeleton)
- Modify: `streamdeck/com.mlapin.marstek.sdPlugin/manifest.json` (two actions, property inspector)

**Consumes:** `Poller`, `Estimator`, `MarstekClient`, `resolve`, `restoreLearned`, `Settings`, `Snapshot`, `levelView`, `etaView`, `etaHours`, `renderKey`, `toDataUri`, `Stabiliser`.

- [ ] **6.1 Write `src/actions/keys.ts`:**

```ts
import { action, SingletonAction, type WillAppearEvent } from "@elgato/streamdeck";

import { Stabiliser } from "../core/format";
import type { Poller } from "../core/poller";
import { renderKey, toDataUri } from "../core/render";
import { etaHours, etaView, type KeyView, levelView, type Snapshot } from "../core/views";

export abstract class BatteryKey extends SingletonAction {
	poller!: Poller;
	#painted?: string;

	protected abstract view(snapshot: Snapshot): KeyView;

	override async onWillAppear(ev: WillAppearEvent): Promise<void> {
		if (!ev.action.isKey()) return;
		await ev.action.setImage(toDataUri(renderKey(this.view(this.poller.snapshot))));
	}

	override async onKeyDown(): Promise<void> {
		await this.poller.kick();
	}

	async repaint(snapshot: Snapshot): Promise<void> {
		const image = toDataUri(renderKey(this.view(snapshot)));
		if (image === this.#painted) return;
		this.#painted = image;
		for (const instance of this.actions) {
			if (instance.isKey()) await instance.setImage(image);
		}
	}
}

@action({ UUID: "com.mlapin.marstek.level" })
export class LevelKey extends BatteryKey {
	protected view(snapshot: Snapshot): KeyView {
		return levelView(snapshot);
	}
}

@action({ UUID: "com.mlapin.marstek.eta" })
export class EtaKey extends BatteryKey {
	#stable = new Stabiliser();

	protected view(snapshot: Snapshot): KeyView {
		return etaView(snapshot, this.#stable.next(etaHours(snapshot.estimate)));
	}
}
```

- [ ] **6.2 Replace `src/plugin.ts`:**

```ts
import streamDeck from "@elgato/streamdeck";

import { EtaKey, LevelKey } from "./actions/keys";
import { MarstekClient } from "./core/client";
import { Estimator } from "./core/estimator";
import { Poller } from "./core/poller";
import { resolve, restoreLearned, type Settings } from "./core/settings";

const SAVE_EVERY_MS = 10 * 60_000;

const estimator = new Estimator();
const keys = [new LevelKey(), new EtaKey()];

const poller = new Poller({
	estimator,
	now: () => Date.now(),
	connect: async () => {
		const settings = resolve(await streamDeck.settings.getGlobalSettings<Settings>());
		return { device: new MarstekClient(settings.host, settings.port), floorPct: settings.floorPct };
	},
	publish: (snapshot) => {
		if (snapshot.error !== undefined) streamDeck.logger.warn(`poll failed: ${snapshot.error} ${snapshot.message ?? ""}`);
		for (const key of keys) void key.repaint(snapshot);
	},
});

for (const key of keys) {
	key.poller = poller;
	streamDeck.actions.registerAction(key);
}

streamDeck.settings.onDidReceiveGlobalSettings<Settings>(() => poller.reconfigure());
streamDeck.system.onSystemDidWakeUp(() => void poller.kick());

await streamDeck.connect();

estimator.restore(restoreLearned(await streamDeck.settings.getGlobalSettings<Settings>()));
poller.start();

setInterval(() => void saveLearned(), SAVE_EVERY_MS);

async function saveLearned(): Promise<void> {
	const stored = await streamDeck.settings.getGlobalSettings<Settings>();
	const learned = estimator.learned;
	if (JSON.stringify(stored.learned) === JSON.stringify(learned)) return;
	await streamDeck.settings.setGlobalSettings<Settings>({ ...stored, learned });
}
```

- [ ] **6.3 Write `ui/settings.html`:**

```html
<!doctype html>
<html>
	<head lang="en">
		<meta charset="utf-8" />
		<script src="sdpi-components.js"></script>
	</head>
	<body>
		<sdpi-item label="Battery IP">
			<sdpi-textfield global setting="host" placeholder="192.168.68.50"></sdpi-textfield>
		</sdpi-item>

		<sdpi-item label="Port">
			<sdpi-textfield global setting="port" placeholder="30000"></sdpi-textfield>
		</sdpi-item>

		<sdpi-item label="Reserve %">
			<sdpi-textfield global setting="floorPercent" placeholder="12"></sdpi-textfield>
		</sdpi-item>
		<sdpi-item>
			<sdpi-item-label></sdpi-item-label>
			<small>
				Turn on Local API in the Marstek app (Settings) and reserve this IP for the battery in the router.
				Reserve is the charge percent at which the battery stops discharging.
			</small>
		</sdpi-item>
	</body>
</html>
```

- [ ] **6.4 Replace the `Actions` array in `manifest.json`:**

```json
"Actions": [
	{
		"Name": "Battery level",
		"UUID": "com.mlapin.marstek.level",
		"Icon": "imgs/actions/battery/icon",
		"Tooltip": "Charge percent and current power.",
		"PropertyInspectorPath": "ui/settings.html",
		"Controllers": ["Keypad"],
		"States": [{ "Image": "imgs/actions/battery/key", "TitleAlignment": "middle" }]
	},
	{
		"Name": "Battery ETA",
		"UUID": "com.mlapin.marstek.eta",
		"Icon": "imgs/actions/battery/icon",
		"Tooltip": "Time until full while charging, time until empty while discharging.",
		"PropertyInspectorPath": "ui/settings.html",
		"Controllers": ["Keypad"],
		"States": [{ "Image": "imgs/actions/battery/key", "TitleAlignment": "middle" }]
	}
]
```

- [ ] **6.5 Build and validate:** `npm run typecheck && npm test && npm run build && npx streamdeck validate com.mlapin.marstek.sdPlugin && npx streamdeck restart com.mlapin.marstek`. Expected: no type errors, 68 passed, validation reports no errors.

- [ ] **6.6 Gate in Stream Deck.** Remove the skeleton key, place the two actions, open one key's settings, type `192.168.68.50`.
  - Before the IP is set every key shows `SET IP`.
  - Within 20 s: `BATTERY` shows the app's percent and `+797W`; the ETA key reads `FULL IN` with a duration while charging, and `ETA` with `FULL` or `—` once idle (no backup load, no history yet).
  - Turn Local API off in the Marstek app: the keys keep their values for about 45 s, then dim with a red dot. Turn it on: they recover within 60 s.
  - Press a key: it refreshes at once.
  - Log: `com.mlapin.marstek.sdPlugin/logs/` has no errors besides the forced outage.

- [ ] **6.7 Commit:** `git add -A && git commit -m "feat: add battery level and eta keys"`

---

## Task 7: Field checks on the real battery

Each check needs you at the battery. Run `MARSTEK_HOST=192.168.68.50 npm run probe` in a terminal during all three; its last column prints the learned values.

- [ ] **7.1 Backup-socket sum.** With the grid connected, plug a kettle into the backup socket and switch it on. Expected: `offgrid_power` rises by the kettle's power and the probe's watts column stays where it was (the mode does not flip to discharging). If the watts column jumps by the kettle's power, `ongrid_power` does not include the pass-through: report it, and the fix is one line in `Estimator.sample` (`acW`) plus its tests.
- [ ] **7.2 Discharge and the reserve.** Unplug the battery from the wall with a steady load of 300–1000 W on the backup socket for 20 minutes. Expected: `EMPTY IN` appears after about 45 s, and after 20 minutes it has dropped by 20 minutes ± 10 %. The learned `dischargeRatio` moves off 1.09 once 150 Wh have been delivered. If you ever run it to shut-off, note the percent it stops at and put it in the Reserve setting.
- [ ] **7.3 Charge to 100 %.** Let one charge run from below 90 % to full with the probe on. Expected: the `taper` array in the last column changes from all 1s if the battery reduces power near the top, and on the next charge `FULL IN` near 90 % lands within 10 minutes of the real finish.
- [ ] **7.4** Record any constant that had to change in this plan's "Device facts", commit, then move the plan to `plans/completed_plans/`.
