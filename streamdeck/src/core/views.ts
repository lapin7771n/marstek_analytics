import type { DeviceErrorKind } from "./client";
import { formatDuration } from "./format";
import type { Estimate } from "./types";

export type PollError = DeviceErrorKind | "settings";

export type Snapshot = { estimate?: Estimate; tempC?: number; error?: PollError; message?: string };

export type Tone = "neutral" | "good" | "warn" | "bad";

export type KeyView = { label: string; value: string; foot: string; tone: Tone; stale: boolean; fill?: number };

const ERROR_TEXT: Record<PollError, string> = {
	blocked: "LAN",
	settings: "SET IP",
	timeout: "NO LINK",
	network: "NO LINK",
	protocol: "ERROR",
};

export function levelView(s: Snapshot): KeyView {
	const est = s.estimate;
	if (est === undefined) return blank("BATTERY", s);

	const watts = Math.round(Math.abs(est.batteryAcW));
	const foot = est.mode === "charging" ? `+${watts}W` : est.mode === "discharging" ? `-${watts}W` : "IDLE";
	const tone: Tone =
		est.mode === "charging" ? "good" : est.mode === "idle" ? "neutral" : est.socPct < 20 ? "bad" : "warn";
	return { label: "BATTERY", value: `${est.socPct}%`, foot, tone, stale: s.error !== undefined, fill: est.socPct / 100 };
}

export function etaHours(est: Estimate | undefined): number | null {
	if (est === undefined) return null;
	return est.mode === "charging" ? est.toFullH : est.toEmptyH;
}

export function etaView(s: Snapshot, hours: number | null): KeyView {
	const est = s.estimate;
	if (est === undefined) return blank("ETA", s);

	const stale = s.error !== undefined;
	const foot = `${Math.round(Math.abs(est.batteryAcW))}W`;
	const value = est.warmingUp || hours === null ? "··" : formatDuration(hours);

	if (est.mode === "charging") return { label: "FULL IN", value, foot, tone: "good", stale };
	if (est.mode === "discharging") {
		return { label: "EMPTY IN", value, foot, tone: hours !== null && hours < 0.5 ? "bad" : "warn", stale };
	}
	if (hours !== null) return { label: "IF OUTAGE", value: formatDuration(hours), foot: "", tone: "neutral", stale };

	const full = est.socPct >= 100;
	return { label: "ETA", value: full ? "FULL" : "—", foot: "", tone: full ? "good" : "neutral", stale };
}

function blank(label: string, s: Snapshot): KeyView {
	return { label, value: s.error === undefined ? "··" : ERROR_TEXT[s.error], foot: "", tone: "neutral", stale: true };
}
