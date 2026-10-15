import type { EsStatus, Estimate } from "./types";

const IDLE_W = 30;
const CHARGE_RATIO = 0.88;
const DISCHARGE_RATIO = 1.09;
const MAX_H = 240;

export function estimate(es: EsStatus, floorPct: number): Estimate {
	const acW = es.ongridW + es.offgridW;
	const capacityWh = (es.socPct / 100) * es.ratedWh;
	const usableWh = Math.max(0, capacityWh - (floorPct / 100) * es.ratedWh);
	const base = { socPct: es.socPct, batteryAcW: acW };

	if (acW < -IDLE_W) {
		const missingWh = Math.max(0, es.ratedWh - capacityWh);
		return { ...base, mode: "charging", hours: capped(missingWh / (-acW * CHARGE_RATIO)) };
	}
	if (acW > IDLE_W) return { ...base, mode: "discharging", hours: capped(usableWh / DISCHARGE_RATIO / acW) };
	if (es.offgridW > IDLE_W) return { ...base, mode: "idle", hours: capped(usableWh / DISCHARGE_RATIO / es.offgridW) };
	return { ...base, mode: "idle", hours: null };
}

function capped(hours: number): number {
	return Math.min(MAX_H, hours);
}
