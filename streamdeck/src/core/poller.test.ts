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
