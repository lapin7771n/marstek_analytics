import { expect, test } from "vitest";

import { resolve, SettingsError } from "./settings";

test("fills the port and floor defaults", () => {
	expect(resolve({ host: " 192.168.68.50 " })).toEqual({ host: "192.168.68.50", port: 30000, floorPct: 12 });
});

test("accepts numbers typed into text fields", () => {
	expect(resolve({ host: "battery.lan", port: "30001", floorPercent: "20" })).toEqual({ host: "battery.lan", port: 30001, floorPct: 20 });
});

test("a cleared text field falls back to its default", () => {
	expect(resolve({ host: "a", port: "", floorPercent: "" })).toEqual({ host: "a", port: 30000, floorPct: 12 });
	expect(resolve({ host: "a", port: " ", floorPercent: " " })).toEqual({ host: "a", port: 30000, floorPct: 12 });
	expect(resolve({ host: "a", floorPercent: "0" }).floorPct).toBe(0);
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
