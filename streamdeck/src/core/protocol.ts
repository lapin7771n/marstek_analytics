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

export function toEsStatus(result: JsonObject, t: number): EsStatus {
	const ratedWh = num(result, "bat_cap");
	if (ratedWh <= 0) throw new ProtocolError(`Reply has bat_cap ${ratedWh}`);
	return {
		t,
		socPct: Math.round(num(result, "bat_soc")),
		ratedWh,
		ongridW: num(result, "ongrid_power"),
		offgridW: num(result, "offgrid_power"),
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
