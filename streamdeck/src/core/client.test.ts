import dgram from "node:dgram";
import { afterEach, expect, test } from "vitest";

import { DeviceError, MarstekClient } from "./client";

type Incoming = { id: number; method: string };
type Fake = { port: number; seen: Incoming[]; close(): void };

const open: Array<{ close(): void }> = [];
afterEach(() => {
	for (const item of open.splice(0)) item.close();
});

async function fake(reply: (msg: Incoming, attempt: number) => string[]): Promise<Fake> {
	const server = dgram.createSocket("udp4");
	const seen: Incoming[] = [];
	server.on("message", (data, from) => {
		const msg = JSON.parse(data.toString("utf8")) as Incoming;
		seen.push(msg);
		for (const out of reply(msg, seen.length)) server.send(out, from.port, from.address);
	});
	await new Promise<void>((done) => server.bind(0, "127.0.0.1", done));
	const device = { port: server.address().port, seen, close: () => server.close() };
	open.push(device);
	return device;
}

function client(port: number): MarstekClient {
	const made = new MarstekClient("127.0.0.1", port, { timeoutMs: 60, gapMs: 5 });
	open.push(made);
	return made;
}

test("returns the result of the matching reply", async () => {
	const device = await fake((msg) => [`{"id":${msg.id},"result":{"bat_soc":80}}`]);
	expect(await client(device.port).call("ES.GetStatus")).toEqual({ bat_soc: 80 });
	expect(device.seen[0].method).toBe("ES.GetStatus");
});

test("ignores a late reply that carries another id", async () => {
	const device = await fake((msg) => [`{"id":${msg.id + 100},"src":"stale"}`, `{"id":${msg.id},"result":{"bat_soc":81}}`]);
	expect(await client(device.port).call("ES.GetStatus")).toEqual({ bat_soc: 81 });
});

test("retries once after a timeout", async () => {
	const device = await fake((msg, attempt) => (attempt === 1 ? [] : [`{"id":${msg.id},"result":{"bat_soc":82}}`]));
	expect(await client(device.port).call("ES.GetStatus")).toEqual({ bat_soc: 82 });
	expect(device.seen).toHaveLength(2);
});

test("two timeouts reject with kind timeout", async () => {
	const device = await fake(() => []);
	const failure = await client(device.port).call("ES.GetStatus").catch((err: Error) => err);
	expect(failure).toBeInstanceOf(DeviceError);
	expect((failure as DeviceError).kind).toBe("timeout");
});

test("a reply with no result rejects with kind protocol", async () => {
	const device = await fake((msg) => [`{"id":${msg.id},"src":"x"}`]);
	const failure = await client(device.port).call("ES.GetStatus").catch((err: Error) => err);
	expect((failure as DeviceError).kind).toBe("protocol");
});

test("calls run one at a time", async () => {
	const device = await fake((msg) => [`{"id":${msg.id},"result":{"n":${msg.id}}}`]);
	const made = client(device.port);
	const [a, b] = await Promise.all([made.call("Bat.GetStatus"), made.call("ES.GetStatus")]);
	expect([a.n, b.n]).toEqual([1, 2]);
	expect(device.seen.map((msg) => msg.method)).toEqual(["Bat.GetStatus", "ES.GetStatus"]);
});

test("a second call waits until the first reply was sent", async () => {
	let inFlight = 0;
	let peak = 0;
	const server = dgram.createSocket("udp4");
	server.on("message", (data, from) => {
		const msg = JSON.parse(data.toString("utf8")) as Incoming;
		peak = Math.max(peak, ++inFlight);
		setTimeout(() => {
			inFlight--;
			server.send(`{"id":${msg.id},"result":{"n":${msg.id}}}`, from.port, from.address);
		}, 20);
	});
	await new Promise<void>((done) => server.bind(0, "127.0.0.1", done));
	open.push({ close: () => server.close() });
	const made = client(server.address().port);
	await Promise.all([made.call("Bat.GetStatus"), made.call("ES.GetStatus")]);
	expect(peak).toBe(1);
});

test("EHOSTUNREACH maps to kind blocked", () => {
	expect(DeviceError.fromSend(Object.assign(new Error("send EHOSTUNREACH"), { code: "EHOSTUNREACH" })).kind).toBe("blocked");
	expect(DeviceError.fromSend(Object.assign(new Error("send ENETDOWN"), { code: "ENETDOWN" })).kind).toBe("network");
});
