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

test("a reply without offgrid_power reads 0 W like the iOS app", () => {
	expect(toEsStatus({ bat_soc: 80, bat_cap: 5120, ongrid_power: -797 }, 0).offgridW).toBe(0);
});

test.each([0, -5120, null])("bat_cap %s with a charge reads as the 5120 Wh Venus rating", (rated) => {
	const result = { bat_soc: 50, bat_cap: rated, ongrid_power: 0, offgrid_power: 0 };
	expect(toEsStatus(result, 0)).toMatchObject({ socPct: 50, ratedWh: 5120 });
});

test("no bat_cap with a charge reads as the 5120 Wh Venus rating", () => {
	expect(toEsStatus({ bat_soc: 50, ongrid_power: 0, offgrid_power: 0 }, 0).ratedWh).toBe(5120);
});

test("bat_soc 0.4 with bat_cap 0 is a charge, read on the raw value", () => {
	expect(toEsStatus({ bat_soc: 0.4, bat_cap: 0, ongrid_power: 0, offgrid_power: 0 }, 0)).toMatchObject({ socPct: 0, ratedWh: 5120 });
});

test("bat_cap 0 and bat_soc 0 is a silent battery management system", () => {
	expect(() => toEsStatus({ bat_soc: 0, bat_cap: 0, ongrid_power: 0, offgrid_power: 0 }, 0)).toThrow(/bat_cap 0/);
});

test("a missing ongrid_power is still a protocol error", () => {
	expect(() => toEsStatus({ bat_soc: 80, bat_cap: 5120, offgrid_power: 0 }, 0)).toThrow(/ongrid_power/);
});

test("non-JSON is a protocol error", () => {
	expect(() => envelope("garbage")).toThrow(ProtocolError);
});
