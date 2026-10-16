import type { EsStatus } from "./types";

export type Json = string | number | boolean | null | Json[] | { [key: string]: Json };
export type JsonObject = { [key: string]: Json };

export class ProtocolError extends Error {}

export function request(id: number, method: string): string {
	return JSON.stringify({ id, method, params: { id: 0 } });
}

export function envelope(text: string): { id: number; body: JsonObject } {
	let body: Json;
	try {
		body = JSON.parse(text) as Json;
	} catch {
		throw new ProtocolError("Reply is not JSON");
	}
	if (!isObject(body) || typeof body.id !== "number") throw new ProtocolError("Reply has no id");
	return { id: body.id, body };
}

export function resultOf(body: JsonObject): JsonObject {
	const { error, result } = body;
	if (isObject(error)) throw new ProtocolError(`Device error ${String(error.code)}: ${String(error.message)}`);
	if (!isObject(result)) throw new ProtocolError("Reply has no result");
	return result;
}

const VENUS_RATED_WH = 5120;

export function toEsStatus(result: JsonObject, t: number): EsStatus {
	const soc = num(result, "bat_soc");
	const rated = optional(result, "bat_cap") ?? 0;
	// A silent battery management system reports bat_cap 0, then bat_soc 0.
	if (rated <= 0 && soc <= 0) throw new ProtocolError(`Reply has bat_cap ${rated}`);
	return {
		t,
		socPct: Math.round(soc),
		ratedWh: rated > 0 ? rated : VENUS_RATED_WH,
		ongridW: num(result, "ongrid_power"),
		offgridW: optional(result, "offgrid_power") ?? 0,
	};
}

function isObject(value: Json | undefined): value is JsonObject {
	return typeof value === "object" && value !== null && !Array.isArray(value);
}

function num(result: JsonObject, key: string): number {
	const value = result[key];
	if (typeof value !== "number" || !Number.isFinite(value)) throw new ProtocolError(`Reply has no ${key}`);
	return value;
}

function optional(result: JsonObject, key: string): number | undefined {
	return result[key] === undefined || result[key] === null ? undefined : num(result, key);
}
