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
	expect(levelView({ estimate: charging })).toMatchObject({ value: "82%", foot: "+797 W", tone: "good", fill: 0.82, stale: false, bolt: true });
	expect(levelView({ estimate: discharging })).toMatchObject({ foot: "−300 W", tone: "warn", bolt: false });
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
	expect(etaView({ estimate: charging }, 1.25)).toMatchObject({ label: "FULL IN", value: "1h20", foot: "797 W", tone: "good" });
	expect(etaView({ estimate: { ...charging, warmingUp: true } }, 1.25).value).toBe("··");
	expect(etaView({ estimate: charging }, 0).value).toBe("0m");
});

test("eta while discharging", () => {
	expect(etaView({ estimate: discharging }, 3.66)).toMatchObject({ label: "EMPTY IN", value: "3h40", foot: "300 W", tone: "warn" });
	expect(etaView({ estimate: discharging }, 0.3).tone).toBe("bad");
	expect(etaView({ estimate: discharging }, 0).value).toBe("0m");
	expect(etaView({ estimate: discharging }, null).value).toBe("··");
});

test("eta while idle is a projection, or the full mark when there is none", () => {
	expect(etaView({ estimate: idle }, 11.2)).toMatchObject({ label: "IF OUTAGE", value: "11h", foot: "BACKUP", tone: "neutral" });
	expect(etaView({ estimate: idle }, null)).toMatchObject({ label: "ETA", value: "FULL", tone: "good" });
	expect(etaView({ estimate: { ...idle, socPct: 60 } }, null).value).toBe("—");
});

test("rendered keys never contain NaN or Infinity and escape markup", () => {
	const svg = renderKey(etaView({ estimate: idle }, 30));
	expect(svg).toContain(">30<");
	expect(svg).toContain(">h<");
	expect(svg).not.toMatch(/NaN|Infinity/);
	expect(renderKey({ ...etaView({ estimate: idle }, 30), value: "<a&b>" })).toContain("&lt;a&amp;b&gt;");
});

test.each([Number.NaN, Number.POSITIVE_INFINITY, Number.NEGATIVE_INFINITY])("an estimate of %f hours shows the placeholder", (hours) => {
	for (const estimate of [{ ...charging, toFullH: hours }, { ...discharging, toEmptyH: hours }]) {
		expect(etaHours(estimate)).toBeNull();
		const view = etaView({ estimate }, etaHours(estimate));
		expect(view.value).toBe("··");
		expect(renderKey(view)).not.toMatch(/NaN|Infinity/);
	}
});

test("a stale key is drawn without the accent colours", () => {
	expect(renderKey(levelView({ estimate: charging }))).toContain("#3DDC97");
	const svg = renderKey(levelView({ estimate: charging, error: "timeout" }));
	expect(svg).not.toContain("#3DDC97");
});
