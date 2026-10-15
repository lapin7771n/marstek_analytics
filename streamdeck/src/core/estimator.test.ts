import { expect, test } from "vitest";

import { estimate } from "./estimator";
import type { EsStatus } from "./types";

const RATED = 5120;

function reading(over: { capacityWh?: number; ongridW: number; offgridW?: number }): EsStatus {
	const socPct = ((over.capacityWh ?? 4121) / RATED) * 100;
	return { t: 0, socPct, ratedWh: RATED, ongridW: over.ongridW, offgridW: over.offgridW ?? 0 };
}

test("discharging counts down to the reserve", () => {
	const est = estimate(reading({ ongridW: 400 }), 12);
	expect(est.mode).toBe("discharging");
	expect(est.hours).toBeCloseTo(8.0427, 3);
});

test("charging counts up to rated", () => {
	const est = estimate(reading({ ongridW: -797 }), 12);
	expect(est.mode).toBe("charging");
	expect(est.hours).toBeCloseTo(1.4244, 3);
});

test("idle with a backup load projects an outage", () => {
	const est = estimate(reading({ ongridW: -150, offgridW: 150 }), 12);
	expect(est.mode).toBe("idle");
	expect(est.hours).toBeCloseTo(21.447, 3);
});

test("idle without a backup load has no eta", () => {
	expect(estimate(reading({ ongridW: 20 }), 12)).toMatchObject({ mode: "idle", hours: null, batteryAcW: 20 });
});

test.each([30, -30])("%d W on the grid is still idle", (ongridW) => {
	expect(estimate(reading({ ongridW }), 12)).toMatchObject({ mode: "idle", hours: null });
});

test("below the reserve is zero, never negative", () => {
	expect(estimate(reading({ capacityWh: 600, ongridW: 400 }), 12).hours).toBe(0);
});

test("full while charging is zero", () => {
	expect(estimate(reading({ capacityWh: 5120, ongridW: -50 }), 12).hours).toBe(0);
});

test("a tiny load is capped", () => {
	expect(estimate(reading({ capacityWh: 10_000, ongridW: 31 }), 0).hours).toBe(240);
});
