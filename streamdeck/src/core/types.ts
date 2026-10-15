export type EsStatus = { t: number; socPct: number; ratedWh: number; ongridW: number; offgridW: number };

export type Mode = "charging" | "discharging" | "idle";

export type Estimate = {
	mode: Mode;
	socPct: number;
	batteryAcW: number;
	hours: number | null;
};
