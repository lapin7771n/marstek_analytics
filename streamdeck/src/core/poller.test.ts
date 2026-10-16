import { afterEach, beforeEach, expect, test, vi } from "vitest";

import { type Device, DeviceError } from "./client";
import { Poller } from "./poller";
import type { JsonObject } from "./protocol";
import { SettingsError } from "./settings";
import type { Snapshot } from "./views";

const ES: JsonObject = { bat_soc: 82, bat_cap: 5120, ongrid_power: -797, offgrid_power: 0 };

class FakeDevice implements Device {
	calls: string[] = [];
	fail?: Error;
	closed = false;
	constructor(readonly es: JsonObject = ES) {}
	call(method: string): Promise<JsonObject> {
		this.calls.push(method);
		if (this.fail !== undefined) return Promise.reject(this.fail);
		return Promise.resolve(this.es);
	}
	close(): void {
		this.closed = true;
	}
}

class HeldDevice extends FakeDevice {
	#pending: Array<{ resolve(reply: JsonObject): void; reject(err: Error): void }> = [];
	override call(method: string): Promise<JsonObject> {
		this.calls.push(method);
		return new Promise((resolve, reject) => this.#pending.push({ resolve, reject }));
	}
	reply(): void {
		this.#pending.shift()?.resolve(this.es);
	}
	reject(err: Error): void {
		this.#pending.shift()?.reject(err);
	}
}

type Connect = () => Promise<{ device: Device; floorPct: number; pollMs: number }>;

function rig(connect?: Connect, pollMs = 60_000) {
	const device = new FakeDevice();
	const published: Snapshot[] = [];
	const poller = new Poller({
		connect: connect ?? (() => Promise.resolve({ device, floorPct: 12, pollMs })),
		now: () => Date.now(),
		publish: (snapshot) => published.push(snapshot),
	});
	return { device, published, poller };
}

function inTurn(...devices: Device[]): { connect: Connect; count(): number } {
	let connects = 0;
	return {
		connect: () => Promise.resolve({ device: devices[Math.min(connects++, devices.length - 1)], floorPct: 12, pollMs: 60_000 }),
		count: () => connects,
	};
}

const flush = () => vi.advanceTimersByTimeAsync(0);

beforeEach(() => vi.useFakeTimers());
afterEach(() => vi.useRealTimers());

test("the first poll sends one ES.GetStatus and publishes the quick estimate", async () => {
	const { device, published, poller } = rig();
	await poller.kick();
	expect(device.calls).toEqual(["ES.GetStatus"]);
	expect(published.at(-1)?.estimate).toEqual({ mode: "charging", socPct: 82, batteryAcW: -797, hours: expect.closeTo(1.314, 3) });
	poller.stop();
});

test("polls every 60 s and sends nothing but ES.GetStatus", async () => {
	const { device, poller } = rig();
	await poller.kick();
	await vi.advanceTimersByTimeAsync(570_000);
	expect(device.calls).toEqual(new Array<string>(10).fill("ES.GetStatus"));
	poller.stop();
});

test("two failed polls keep the last reading; the third marks it stale", async () => {
	const { device, published, poller } = rig();
	await poller.kick();
	device.fail = new DeviceError("timeout", "No reply");

	await vi.advanceTimersByTimeAsync(60_000);
	await vi.advanceTimersByTimeAsync(60_000);
	expect(published.at(-1)?.error).toBeUndefined();

	await vi.advanceTimersByTimeAsync(60_000);
	expect(published.at(-1)).toMatchObject({ error: "timeout", estimate: { socPct: 82 } });
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
	const device = new FakeDevice({ ...ES, bat_soc: 50, ongrid_power: 400 });
	let bad = true;
	const { published, poller } = rig(() =>
		bad ? Promise.reject(new SettingsError("Set the battery IP in the key settings")) : Promise.resolve({ device, floorPct: 20, pollMs: 60_000 }),
	);
	await poller.kick();
	expect(published.at(-1)).toMatchObject({ error: "settings", message: "Set the battery IP in the key settings" });

	bad = false;
	poller.reconfigure();
	await poller.kick();
	expect(published.at(-1)?.estimate?.socPct).toBe(50);
	expect(published.at(-1)?.estimate?.hours).toBeCloseTo(3.5229, 3);
	poller.stop();
});

test("reconfigure closes the working device and polls the new one", async () => {
	const a = new FakeDevice();
	const b = new FakeDevice({ ...ES, bat_soc: 40 });
	const devices = inTurn(a, b);
	const { published, poller } = rig(devices.connect);
	await poller.kick();
	expect(a.calls).toEqual(["ES.GetStatus"]);

	poller.reconfigure();
	await flush();
	expect(a.closed).toBe(true);
	expect(devices.count()).toBe(2);
	expect(a.calls).toHaveLength(1);
	expect(b.calls).toEqual(["ES.GetStatus"]);
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
	expect(b.calls).toEqual(["ES.GetStatus"]);
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
	let connected: (made: { device: Device; floorPct: number; pollMs: number }) => void = () => {};
	const { published, poller } = rig(() => new Promise((resolve) => (connected = resolve)));
	void poller.kick();
	await flush();

	poller.stop();
	connected({ device: late, floorPct: 12, pollMs: 60_000 });
	await flush();
	expect(late.closed).toBe(true);
	expect(late.calls).toEqual([]);
	expect(published).toEqual([]);
});

test("overlapping kicks share one poll", async () => {
	const { device, poller } = rig();
	await Promise.all([poller.kick(), poller.kick()]);
	expect(device.calls).toEqual(["ES.GetStatus"]);
	poller.stop();
});

test("with pollMs 900 000 the device gets one call by 899 s and two at 900 s", async () => {
	const { device, poller } = rig(undefined, 900_000);
	await poller.kick();
	expect(device.calls).toHaveLength(1);
	await vi.advanceTimersByTimeAsync(899_000);
	expect(device.calls).toHaveLength(1);
	await vi.advanceTimersByTimeAsync(1_000);
	expect(device.calls).toHaveLength(2);
	poller.stop();
});

test("after three failures in Infrequent mode the gap stays 900 s", async () => {
	const { device, published, poller } = rig(undefined, 900_000);
	await poller.kick();
	device.fail = new DeviceError("timeout", "No reply");
	await vi.advanceTimersByTimeAsync(2_700_000);
	expect(device.calls).toHaveLength(4);
	expect(published.at(-1)?.error).toBe("timeout");

	await vi.advanceTimersByTimeAsync(899_000);
	expect(device.calls).toHaveLength(4);
	await vi.advanceTimersByTimeAsync(1_000);
	expect(device.calls).toHaveLength(5);
	poller.stop();
});

test("a reconfigure applies the new interval", async () => {
	const device = new FakeDevice();
	let pollMs = 900_000;
	const { poller } = rig(() => Promise.resolve({ device, floorPct: 12, pollMs }));
	await poller.kick();

	pollMs = 60_000;
	poller.reconfigure();
	await flush();
	expect(device.calls).toHaveLength(2);
	await vi.advanceTimersByTimeAsync(59_000);
	expect(device.calls).toHaveLength(2);
	await vi.advanceTimersByTimeAsync(1_000);
	expect(device.calls).toHaveLength(3);
	poller.stop();
});

test("before a connect has set the interval the poller waits 60 s between polls", async () => {
	let connects = 0;
	const poller = new Poller({
		connect: () => {
			connects++;
			return Promise.reject(new SettingsError("Set the battery IP in the key settings"));
		},
		now: () => Date.now(),
		publish: () => {},
	});
	await poller.kick();
	await vi.advanceTimersByTimeAsync(59_000);
	expect(connects).toBe(1);
	await vi.advanceTimersByTimeAsync(1_000);
	expect(connects).toBe(2);
	poller.stop();
});
