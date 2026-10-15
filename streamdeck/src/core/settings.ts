export type Settings = {
	host?: string;
	port?: string | number;
	floorPercent?: string | number;
};

export type Resolved = { host: string; port: number; floorPct: number };

export class SettingsError extends Error {}

const HOST = /^[A-Za-z0-9.-]+$/;

export function resolve(settings: Settings): Resolved {
	const host = settings.host?.trim() ?? "";
	if (!HOST.test(host)) throw new SettingsError("Set the battery IP in the key settings");

	const port = Number(filled(settings.port) ?? 30000);
	if (!Number.isInteger(port) || port < 1 || port > 65535) throw new SettingsError("Port must be 1 to 65535");

	const floorPct = Number(filled(settings.floorPercent) ?? 12);
	if (!Number.isFinite(floorPct) || floorPct < 0 || floorPct > 50) throw new SettingsError("Reserve must be 0 to 50 percent");

	return { host, port, floorPct };
}

function filled(value: string | number | undefined): string | number | undefined {
	if (typeof value !== "string") return value;
	const text = value.trim();
	return text === "" ? undefined : text;
}
