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
