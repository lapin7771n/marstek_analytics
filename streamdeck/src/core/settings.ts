export type Settings = {
	host?: string;
	port?: string | number;
	floorPercent?: string | number;
	pollSeconds?: string | number;
};

export type Resolved = { host: string; port: number; floorPct: number; pollMs: number };

export class SettingsError extends Error {}

const POLL_SECONDS = [60, 300, 900];
const HOST = /^[A-Za-z0-9.-]+$/;

export function resolve(settings: Settings): Resolved {
	const host = settings.host?.trim() ?? "";
	if (!HOST.test(host)) throw new SettingsError("Set the battery IP in the key settings");

	const port = Number(filled(settings.port) ?? 30000);
	if (!Number.isInteger(port) || port < 1 || port > 65535) throw new SettingsError("Port must be 1 to 65535");

	const floorPct = Number(filled(settings.floorPercent) ?? 12);
	if (!Number.isFinite(floorPct) || floorPct < 0 || floorPct > 50) throw new SettingsError("Reserve must be 0 to 50 percent");

	const pollSeconds = Number(filled(settings.pollSeconds) ?? 60);
	if (!POLL_SECONDS.includes(pollSeconds)) throw new SettingsError("Poll interval must be 60, 300 or 900 s");

	return { host, port, floorPct, pollMs: pollSeconds * 1000 };
}

function filled(value: string | number | undefined): string | number | undefined {
	if (typeof value !== "string") return value;
	const text = value.trim();
	return text === "" ? undefined : text;
}
