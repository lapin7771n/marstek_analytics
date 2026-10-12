export type EsStatus = { t: number; socPct: number; ongridW: number; offgridW: number };

export type BatStatus = { t: number; capacityWh: number; ratedWh: number; tempC: number };

export type Mode = "charging" | "discharging" | "idle";

export type Estimate = {
	mode: Mode;
	socPct: number;
	batteryAcW: number;
	toFullH: number | null;
	toEmptyH: number | null;
	projected: boolean;
	warmingUp: boolean;
};

export type Learned = {
	chargeRatio: number;
	dischargeRatio: number;
	typicalLoadW: number | null;
	taper: number[];
};
