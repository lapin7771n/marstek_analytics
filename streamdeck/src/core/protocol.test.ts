import { expect, test } from "vitest";

import { envelope, ProtocolError, request, resultOf, toBatStatus, toEsStatus } from "./protocol";

const ES = `{"id":2,"src":"VenusE 3.0-bc2a3314ce8d","result":{"id":0,"bat_soc":80,"bat_cap":5120,"pv_power":0,"ongrid_power":-797,"offgrid_power":0,"total_grid_input_energy":47029}}`;
const BAT = `{"id":3,"src":"VenusE 3.0-bc2a3314ce8d","result":{"id":0,"soc":80,"charg_flag":true,"dischrg_flag":true,"bat_temp":24.0,"bat_capacity":4121.0,"rated_capacity":5120.0}}`;

test("request addresses instance 0", () => {
	expect(JSON.parse(request(7, "ES.GetStatus"))).toEqual({ id: 7, method: "ES.GetStatus", params: { id: 0 } });
});

test("parses the ES.GetStatus reply captured from the device", () => {
	const { id, body } = envelope(ES);
	expect(id).toBe(2);
	expect(toEsStatus(resultOf(body), 1000)).toEqual({ t: 1000, socPct: 80, ongridW: -797, offgridW: 0 });
});

test("parses the Bat.GetStatus reply captured from the device", () => {
	expect(toBatStatus(resultOf(envelope(BAT).body), 1000)).toEqual({ t: 1000, capacityWh: 4121, ratedWh: 5120, tempC: 24 });
});

test("a reply with no result is a protocol error", () => {
	expect(() => resultOf(envelope(`{"id":2,"src":"x"}`).body)).toThrow(ProtocolError);
});

test("a device error carries its code", () => {
	expect(() => resultOf(envelope(`{"id":2,"error":{"code":-32601,"message":"Method not found"}}`).body)).toThrow(/-32601/);
});

test("a missing field is a protocol error, never a zero", () => {
	expect(() => toEsStatus({ bat_soc: 80, ongrid_power: -797 }, 0)).toThrow(/offgrid_power/);
});

test.each([0, -5120])("a rated capacity of %d is a protocol error", (rated) => {
	expect(() => toBatStatus({ bat_capacity: 2560, rated_capacity: rated, bat_temp: 24 }, 0)).toThrow(ProtocolError);
	expect(() => toBatStatus({ bat_capacity: 2560, rated_capacity: rated, bat_temp: 24 }, 0)).toThrow(/rated_capacity/);
});

test("non-JSON is a protocol error", () => {
	expect(() => envelope("garbage")).toThrow(ProtocolError);
});
