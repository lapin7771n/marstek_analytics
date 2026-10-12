import { expect, test } from "vitest";

import { defaultLearned } from "./estimator";
import { resolve, restoreLearned, SettingsError } from "./settings";

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

test("restores learned values that are in range", () => {
	const learned = { chargeRatio: 0.9, dischargeRatio: 1.1, typicalLoadW: 350, taper: [1, 1, 1, 1, 1, 0.8, 0.6, 0.5, 0.4, 0.3] };
	expect(restoreLearned({ learned })).toEqual(learned);
});

test("falls back to defaults when learned values are damaged", () => {
	expect(restoreLearned({})).toEqual(defaultLearned());
	expect(restoreLearned({ learned: { ...defaultLearned(), taper: [1, 2] } })).toEqual(defaultLearned());
	expect(restoreLearned({ learned: { ...defaultLearned(), chargeRatio: 5 } })).toEqual(defaultLearned());
});
