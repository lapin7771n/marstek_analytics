import { expect, test } from "vitest";

import { resolve, SettingsError } from "./settings";

test("fills the port and floor defaults", () => {
	expect(resolve({ host: " 192.168.68.50 " })).toEqual({ host: "192.168.68.50", port: 30000, floorPct: 12, pollMs: 60_000 });
});

test("accepts numbers typed into text fields", () => {
	expect(resolve({ host: "battery.lan", port: "30001", floorPercent: "20" })).toEqual({
		host: "battery.lan",
		port: 30001,
		floorPct: 20,
		pollMs: 60_000,
	});
});

test("a cleared text field falls back to its default", () => {
	expect(resolve({ host: "a", port: "", floorPercent: "", pollSeconds: "" })).toEqual({ host: "a", port: 30000, floorPct: 12, pollMs: 60_000 });
	expect(resolve({ host: "a", port: " ", floorPercent: " ", pollSeconds: " " })).toEqual({ host: "a", port: 30000, floorPct: 12, pollMs: 60_000 });
	expect(resolve({ host: "a", floorPercent: "0" }).floorPct).toBe(0);
});

test("the poll interval maps seconds to milliseconds", () => {
	expect(resolve({ host: "a", pollSeconds: "60" }).pollMs).toBe(60_000);
	expect(resolve({ host: "a", pollSeconds: 300 }).pollMs).toBe(300_000);
	expect(resolve({ host: "a", pollSeconds: "900" }).pollMs).toBe(900_000);
});

test.each([
	[{}, /battery IP/],
	[{ host: "192.168.68.50; rm" }, /battery IP/],
	[{ host: "a", port: "70000" }, /Port/],
	[{ host: "a", port: "abc" }, /Port/],
	[{ host: "a", floorPercent: "90" }, /Reserve/],
	[{ host: "a", pollSeconds: "15" }, /Poll interval must be 60, 300 or 900 s/],
])("rejects %j", (settings, message) => {
	expect(() => resolve(settings)).toThrow(SettingsError);
	expect(() => resolve(settings)).toThrow(message);
});
