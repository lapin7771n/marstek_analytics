import { expect, test } from "vitest";

import { envelope, ProtocolError, request, resultOf, toEsStatus } from "./protocol";

const ES = `{"id":2,"src":"VenusE 3.0-bc2a3314ce8d","result":{"id":0,"bat_soc":80,"bat_cap":5120,"pv_power":0,"ongrid_power":-797,"offgrid_power":0,"total_grid_input_energy":47029}}`;

test("request addresses instance 0", () => {
	expect(JSON.parse(request(7, "ES.GetStatus"))).toEqual({ id: 7, method: "ES.GetStatus", params: { id: 0 } });
});

test("parses the ES.GetStatus reply captured from the device", () => {
	const { id, body } = envelope(ES);
	expect(id).toBe(2);
	expect(toEsStatus(resultOf(body), 1000)).toEqual({ t: 1000, socPct: 80, ratedWh: 5120, ongridW: -797, offgridW: 0 });
});

test("a fractional bat_soc is rounded like the iOS app", () => {
	const result = { bat_soc: 99.6, bat_cap: 5120, ongrid_power: 0, offgrid_power: 0 };
	expect(toEsStatus(result, 0).socPct).toBe(100);
});

test("a reply with no result is a protocol error", () => {
	expect(() => resultOf(envelope(`{"id":2,"src":"x"}`).body)).toThrow(ProtocolError);
});

test("a device error carries its code", () => {
	expect(() => resultOf(envelope(`{"id":2,"error":{"code":-32601,"message":"Method not found"}}`).body)).toThrow(/-32601/);
});

test("a missing field is a protocol error, never a zero", () => {
	expect(() => toEsStatus({ bat_soc: 80, bat_cap: 5120, ongrid_power: -797 }, 0)).toThrow(/offgrid_power/);
});

test.each([0, -5120])("a rated capacity of %d is a protocol error", (rated) => {
	const result = { bat_soc: 50, bat_cap: rated, ongrid_power: 0, offgrid_power: 0 };
	expect(() => toEsStatus(result, 0)).toThrow(ProtocolError);
	expect(() => toEsStatus(result, 0)).toThrow(/bat_cap/);
});

test("a reply without bat_cap is a protocol error", () => {
	expect(() => toEsStatus({ bat_soc: 50, ongrid_power: 0, offgrid_power: 0 }, 0)).toThrow(/bat_cap/);
});

test("non-JSON is a protocol error", () => {
	expect(() => envelope("garbage")).toThrow(ProtocolError);
});
