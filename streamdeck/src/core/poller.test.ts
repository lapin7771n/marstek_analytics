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
	times: number[] = [];
	fail?: Error;
	failOnly?: string;
	closed = false;
	constructor(readonly es: JsonObject = ES) {}
	call(method: string): Promise<JsonObject> {
		this.calls.push(method);
		this.times.push(Date.now());
		if (this.fail !== undefined && (this.failOnly === undefined || this.failOnly === method)) return Promise.reject(this.fail);
		return Promise.resolve(method === "ES.GetStatus" ? this.es : BAT);
	}
	close(): void {
		this.closed = true;
	}
}

class HeldDevice extends FakeDevice {
	#pending: Array<{ method: string; resolve(reply: JsonObject): void; reject(err: Error): void }> = [];
	override call(method: string): Promise<JsonObject> {
		this.calls.push(method);
		return new Promise((resolve, reject) => this.#pending.push({ method, resolve, reject }));
	}
	reply(): void {
		const next = this.#pending.shift();
		next?.resolve(next.method === "ES.GetStatus" ? this.es : BAT);
	}
	reject(err: Error): void {
		this.#pending.shift()?.reject(err);
	}
}

type Connect = () => Promise<{ device: Device; floorPct: number }>;

function rig(connect?: Connect) {
	const device = new FakeDevice();
	const published: Snapshot[] = [];
	const estimator = new Estimator();
	const poller = new Poller({
		connect: connect ?? (() => Promise.resolve({ device, floorPct: 12 })),
		now: () => Date.now(),
		publish: (snapshot) => published.push(snapshot),
		estimator,
	});
	return { device, published, poller, estimator };
}

function inTurn(...devices: Device[]): { connect: Connect; count(): number } {
	let connects = 0;
	return {
		connect: () => Promise.resolve({ device: devices[Math.min(connects++, devices.length - 1)], floorPct: 12 }),
		count: () => connects,
	};
}

const flush = () => vi.advanceTimersByTimeAsync(0);

function sent(device: FakeDevice, method: string, since = 0): number[] {
	return device.times.filter((_, i) => device.calls[i] === method && device.times[i] >= since).map((t) => t - since);
}

beforeEach(() => vi.useFakeTimers());
afterEach(() => vi.useRealTimers());

test("the first poll reads the battery and publishes an estimate", async () => {
	const { device, published, poller } = rig();
	await poller.kick();
	expect(device.calls).toEqual(["ES.GetStatus", "Bat.GetStatus"]);
	expect(published.at(-1)?.estimate?.socPct).toBe(82);
	expect(published.at(-1)?.tempC).toBe(24);
	poller.stop();
});

test("polls every 15 s and reads the capacity every 5 minutes", async () => {
	const { device, poller } = rig();
	await poller.kick();
	await vi.advanceTimersByTimeAsync(285_000);
	expect(device.calls).toEqual(["ES.GetStatus", "Bat.GetStatus", ...new Array<string>(19).fill("ES.GetStatus")]);
	await vi.advanceTimersByTimeAsync(15_000);
	expect(device.calls.slice(21)).toEqual(["ES.GetStatus", "Bat.GetStatus"]);
	poller.stop();
});

test("a failed capacity read keeps polling and retries the capacity after 60 s", async () => {
	const { device, published, poller } = rig();
	device.fail = new DeviceError("timeout", "No reply");
	device.failOnly = "Bat.GetStatus";
	await poller.kick();
	expect(device.calls).toEqual(["ES.GetStatus", "Bat.GetStatus"]);
	expect(published.at(-1)?.error).toBeUndefined();
	expect(published.at(-1)?.estimate?.socPct).toBe(82);

	await vi.advanceTimersByTimeAsync(45_000);
	expect(device.calls.slice(2)).toEqual(["ES.GetStatus", "ES.GetStatus", "ES.GetStatus"]);
	await vi.advanceTimersByTimeAsync(15_000);
	expect(device.calls.slice(5)).toEqual(["ES.GetStatus", "Bat.GetStatus"]);
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
	const { published, poller, estimator } = rig(() =>
		bad ? Promise.reject(new SettingsError("Set the battery IP in the key settings")) : Promise.resolve({ device, floorPct: 20 }),
	);
	await poller.kick();
	expect(published.at(-1)).toMatchObject({ error: "settings", message: "Set the battery IP in the key settings" });
	expect(estimator.floorPct).toBe(12);

	bad = false;
	poller.reconfigure();
	await poller.kick();
	expect(published.at(-1)?.estimate?.socPct).toBe(82);
	expect(estimator.floorPct).toBe(20);
	poller.stop();
});

test("reconfigure closes the working device and polls the new one", async () => {
	const a = new FakeDevice();
	const b = new FakeDevice({ ...ES, bat_soc: 40 });
	const devices = inTurn(a, b);
	const { published, poller } = rig(devices.connect);
	await poller.kick();
	expect(a.calls).toEqual(["ES.GetStatus", "Bat.GetStatus"]);

	poller.reconfigure();
	await flush();
	expect(a.closed).toBe(true);
	expect(devices.count()).toBe(2);
	expect(a.calls).toHaveLength(2);
	expect(b.calls).toEqual(["ES.GetStatus", "Bat.GetStatus"]);
	expect(published.at(-1)?.estimate?.socPct).toBe(40);
	poller.stop();
});

test("stop closes the device", async () => {
	const { device, poller } = rig();
	await poller.kick();
	expect(device.closed).toBe(false);
	poller.stop();
	expect(device.closed).toBe(true);
});

test("a reconfigure during a poll discards that poll and polls the new device at once", async () => {
	const a = new HeldDevice();
	const b = new FakeDevice({ ...ES, bat_soc: 40 });
	const { published, poller } = rig(inTurn(a, b).connect);
	void poller.kick();
	await flush();
	expect(a.calls).toEqual(["ES.GetStatus"]);

	poller.reconfigure();
	a.reply();
	await flush();
	expect(a.calls).toEqual(["ES.GetStatus"]);
	expect(published.map((snapshot) => snapshot.estimate?.socPct)).toEqual([40]);
	expect(b.calls).toEqual(["ES.GetStatus", "Bat.GetStatus"]);
	poller.stop();
});

test("a reconfigure while the capacity is being read sends nothing more to the old device", async () => {
	const a = new HeldDevice();
	const b = new FakeDevice();
	const { published, poller } = rig(inTurn(a, b).connect);
	void poller.kick();
	await flush();
	a.reply();
	await flush();
	expect(a.calls).toEqual(["ES.GetStatus", "Bat.GetStatus"]);

	poller.reconfigure();
	a.reply();
	await flush();
	expect(a.calls).toEqual(["ES.GetStatus", "Bat.GetStatus"]);
	expect(published).toHaveLength(1);
	expect(b.calls).toEqual(["ES.GetStatus", "Bat.GetStatus"]);
	poller.stop();
});

test("a call that the reconfigure cut off is not a failed poll", async () => {
	const a = new HeldDevice();
	const b = new HeldDevice();
	const { published, poller } = rig(inTurn(a, b).connect);
	void poller.kick();
	await flush();

	poller.reconfigure();
	a.reject(new DeviceError("blocked", "Client is closed"));
	await flush();
	expect(published).toEqual([]);
	expect(b.calls).toEqual(["ES.GetStatus"]);
	poller.stop();
});

test("a device that connects after stop is closed unused", async () => {
	const late = new FakeDevice();
	let connected: (made: { device: Device; floorPct: number }) => void = () => {};
	const { published, poller } = rig(() => new Promise((resolve) => (connected = resolve)));
	void poller.kick();
	await flush();

	poller.stop();
	connected({ device: late, floorPct: 12 });
	await flush();
	expect(late.closed).toBe(true);
	expect(late.calls).toEqual([]);
	expect(published).toEqual([]);
});

test("after two minutes without a reading the next good poll reads the capacity", async () => {
	const { device, poller } = rig();
	await poller.kick();
	device.fail = new DeviceError("timeout", "No reply");
	await vi.advanceTimersByTimeAsync(105_000);
	expect(device.calls.slice(2)).toEqual(new Array<string>(4).fill("ES.GetStatus"));
	device.fail = undefined;
	await vi.advanceTimersByTimeAsync(60_000);
	expect(device.calls.slice(6)).toEqual(["ES.GetStatus", "Bat.GetStatus"]);
	poller.stop();
});

test("while the battery is down only ES.GetStatus goes out, once a minute", async () => {
	const { device, poller } = rig();
	const start = Date.now();
	await poller.kick();
	device.fail = new DeviceError("timeout", "No reply");
	await vi.advanceTimersByTimeAsync(600_000);
	expect(sent(device, "Bat.GetStatus", start)).toEqual([0]);
	expect(sent(device, "ES.GetStatus", start)).toEqual([0, 15, 30, 45, 105, 165, 225, 285, 345, 405, 465, 525, 585].map((s) => s * 1000));
	poller.stop();
});

test("the first poll after a 3-minute sleep reads the capacity", async () => {
	const { device, poller } = rig();
	await poller.kick();
	await vi.advanceTimersByTimeAsync(15_000);
	expect(device.calls).toEqual(["ES.GetStatus", "Bat.GetStatus", "ES.GetStatus"]);
	vi.setSystemTime(Date.now() + 180_000);
	await vi.advanceTimersByTimeAsync(15_000);
	expect(device.calls.slice(3)).toEqual(["ES.GetStatus", "Bat.GetStatus"]);
	poller.stop();
});

test("a capacity read that keeps failing backs off to once every 5 minutes", async () => {
	const { device, poller } = rig();
	const start = Date.now();
	device.fail = new DeviceError("timeout", "No reply");
	device.failOnly = "Bat.GetStatus";
	await poller.kick();
	await vi.advanceTimersByTimeAsync(1_080_000);
	expect(sent(device, "Bat.GetStatus", start)).toEqual([0, 60, 180, 420, 720, 1020].map((s) => s * 1000));
	poller.stop();
});

test("with a known capacity a failed capacity read waits the full 5 minutes", async () => {
	const { device, poller } = rig();
	const start = Date.now();
	await poller.kick();
	device.fail = new DeviceError("timeout", "No reply");
	device.failOnly = "Bat.GetStatus";
	await vi.advanceTimersByTimeAsync(960_000);
	expect(sent(device, "Bat.GetStatus", start)).toEqual([0, 300, 600, 900].map((s) => s * 1000));
	poller.stop();
});

test("a clock stepped back reads the capacity at once", async () => {
	const { device, poller } = rig();
	await poller.kick();
	await vi.advanceTimersByTimeAsync(15_000);
	vi.setSystemTime(Date.now() - 3600_000);
	await vi.advanceTimersByTimeAsync(15_000);
	expect(device.calls).toEqual(["ES.GetStatus", "Bat.GetStatus", "ES.GetStatus", "ES.GetStatus", "Bat.GetStatus"]);
	poller.stop();
});

test("the first poll after reconfigure reads the capacity", async () => {
	const { device, poller } = rig();
	await poller.kick();
	poller.reconfigure();
	await flush();
	expect(device.calls).toEqual(["ES.GetStatus", "Bat.GetStatus", "ES.GetStatus", "Bat.GetStatus"]);
	poller.stop();
});

test("the first poll after a sleep reads the capacity before it estimates", async () => {
	const { device, poller } = rig();
	await poller.kick();

	vi.setSystemTime(Date.now() + 8 * 3600_000);
	await poller.kick();
	expect(device.calls).toEqual(["ES.GetStatus", "Bat.GetStatus", "ES.GetStatus", "Bat.GetStatus"]);
	poller.stop();
});

test("overlapping kicks share one poll", async () => {
	const { device, poller } = rig();
	await Promise.all([poller.kick(), poller.kick()]);
	expect(device.calls).toEqual(["ES.GetStatus", "Bat.GetStatus"]);
	poller.stop();
});
