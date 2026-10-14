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
		readonly batEveryS = 30,
	) {}

	run(...phases: Phase[]): Estimate {
		for (const phase of phases) {
			for (let elapsed = 0; elapsed < phase.seconds; elapsed += STEP_S) {
				const offgridW = phase.offgridW ?? 0;
				const acW = phase.ongridW + offgridW;
				const ratio = acW < 0 ? this.storeRatio : this.drainRatio;
				if (this.t > 0) this.capacityWh = Math.min(RATED, this.capacityWh - (acW * ratio * STEP_S) / 3600);
				if (this.t % this.batEveryS === 0) {
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

test("on grid at the floor the projection is zero, never negative", () => {
	const rig = new Rig(new Estimator(), 0.1 * RATED);
	const got = rig.run({ seconds: 60, ongridW: -400, offgridW: 400 });
	expect(got.projected).toBe(true);
	expect(got.toEmptyH).toBe(0);
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

test("a capacity change across a gap is not learned as a ratio", () => {
	const est = new Estimator();
	const rig = new Rig(est, 2000);
	rig.run({ seconds: 720, ongridW: -800 });
	rig.t += 3 * 3600;
	rig.capacityWh += 10;
	rig.run({ seconds: 15, ongridW: -800 });
	expect(est.learned.chargeRatio).toBe(0.88);
});

test("a ratio outside the plausible range is discarded, not clamped", () => {
	const charge = new Estimator();
	const charging = new Rig(charge, 2000);
	charging.run({ seconds: 690, ongridW: -800 });
	charging.capacityWh += 200;
	charging.run({ seconds: 45, ongridW: -800 });
	expect(charge.learned.chargeRatio).toBe(0.88);

	const discharge = new Estimator();
	const discharging = new Rig(discharge, 4500);
	discharging.run({ seconds: 690, ongridW: 0, offgridW: 800 });
	discharging.capacityWh -= 200;
	discharging.run({ seconds: 45, ongridW: 0, offgridW: 800 });
	expect(discharge.learned.dischargeRatio).toBe(1.09);
});

test("a ratio inside the range is still learned after a discarded one", () => {
	const est = new Estimator();
	const rig = new Rig(est, 2000, 0.8);
	rig.run({ seconds: 690, ongridW: -800 });
	rig.capacityWh += 200;
	rig.run({ seconds: 750, ongridW: -800 });
	expect(est.learned.chargeRatio).toBeCloseTo(0.88 + 0.2 * (0.8 - 0.88), 3);
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

test("between capacity reads the time to full follows the energy stored, above 90 % too", () => {
	const phase = { seconds: 1500, ongridW: -2000 };
	const everyRig = new Rig(new Estimator(), 4000);
	const every = everyRig.run(phase).toFullH ?? 0;
	const rare = new Rig(new Estimator(), 4000, 0.88, 1.09, 300).run(phase).toFullH ?? 0;
	expect(everyRig.capacityWh / RATED).toBeGreaterThan(0.9);
	expect(Math.abs(rare - every)).toBeLessThan(0.005);
});

test("a hole in the readings is not learned as a discharge ratio", () => {
	const est = new Estimator();
	const sample = (s: number) => est.sample({ t: s * 1000, socPct: 80, ongridW: 0, offgridW: 1500 });
	const battery = (s: number) =>
		est.battery({ t: s * 1000, capacityWh: 4500 - (1500 * 1.09 * s) / 3600, ratedWh: RATED, tempC: 24 });
	sample(0);
	battery(15);
	for (let s = 15; s <= 450; s += 15) sample(s);
	battery(585);
	sample(585);
	expect(est.learned.dischargeRatio).toBe(1.09);
});

test("after a gap there is no runtime until a fresh capacity read", () => {
	const est = new Estimator();
	const sample = (s: number) => est.sample({ t: s * 1000, socPct: 80, ongridW: 0, offgridW: 300 });
	sample(0);
	est.battery({ t: 15_001, capacityWh: 4000, ratedWh: RATED, tempC: 24 });
	expect(sample(15).toEmptyH).not.toBeNull();
	expect(sample(15 + 8 * 3600).toEmptyH).toBeNull();
	est.battery({ t: (30 + 8 * 3600) * 1000 + 1, capacityWh: 1000, ratedWh: RATED, tempC: 24 });
	expect(sample(30 + 8 * 3600).toEmptyH).not.toBeNull();
});
