import { defaultLearned } from "./estimator";
import type { Learned } from "./types";

export type Settings = {
	host?: string;
	port?: string | number;
	floorPercent?: string | number;
	learned?: Learned;
};

export type Resolved = { host: string; port: number; floorPct: number };

export class SettingsError extends Error {}

const HOST = /^[A-Za-z0-9.-]+$/;

export function resolve(settings: Settings): Resolved {
	const host = settings.host?.trim() ?? "";
	if (!HOST.test(host)) throw new SettingsError("Set the battery IP in the key settings");

	const port = Number(settings.port ?? 30000);
	if (!Number.isInteger(port) || port < 1 || port > 65535) throw new SettingsError("Port must be 1 to 65535");

	const floorPct = Number(settings.floorPercent ?? 12);
	if (!Number.isFinite(floorPct) || floorPct < 0 || floorPct > 50) throw new SettingsError("Reserve must be 0 to 50 percent");

	return { host, port, floorPct };
}

export function restoreLearned(settings: Settings): Learned {
	const learned = settings.learned;
	if (learned === undefined) return defaultLearned();

	const taperOk =
		Array.isArray(learned.taper) && learned.taper.length === 10 && learned.taper.every((value) => inRange(value, 0.05, 1));
	const typicalOk = learned.typicalLoadW === null || inRange(learned.typicalLoadW, 0, 10_000);
	const ok = taperOk && typicalOk && inRange(learned.chargeRatio, 0.7, 1) && inRange(learned.dischargeRatio, 1, 1.5);

	return ok ? { ...learned, taper: [...learned.taper] } : defaultLearned();
}

function inRange(value: number, low: number, high: number): boolean {
	return typeof value === "number" && Number.isFinite(value) && value >= low && value <= high;
}
