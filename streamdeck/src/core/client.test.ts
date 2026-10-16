import dgram from "node:dgram";
import { afterEach, expect, test, vi } from "vitest";

import { DeviceError, MarstekClient } from "./client";

type Incoming = { id: number; method: string };
type Fake = { port: number; seen: Incoming[]; arrived: number[]; replied: number[]; close(): void };
type Options = { timeoutMs?: number; gapMs?: number };

const TIMEOUT_MS = 60;
const TIMER_SLACK_MS = 2;

const open: Array<{ close(): void }> = [];
afterEach(() => {
	vi.restoreAllMocks();
	for (const item of open.splice(0)) item.close();
});

const sleep = (ms: number) => new Promise<void>((done) => setTimeout(done, ms));

async function fake(reply: (msg: Incoming, attempt: number) => string[]): Promise<Fake> {
	const server = dgram.createSocket("udp4");
	const seen: Incoming[] = [];
	const arrived: number[] = [];
	const replied: number[] = [];
	server.on("message", (data, from) => {
		arrived.push(performance.now());
		const msg = JSON.parse(data.toString("utf8")) as Incoming;
		seen.push(msg);
		for (const out of reply(msg, seen.length)) server.send(out, from.port, from.address);
		replied.push(performance.now());
	});
	await new Promise<void>((done) => server.bind(0, "127.0.0.1", done));
	const device = { port: server.address().port, seen, arrived, replied, close: () => server.close() };
	open.push(device);
	return device;
}

function client(port: number, options: Options = {}, host = "127.0.0.1"): MarstekClient {
	const made = new MarstekClient(host, port, { timeoutMs: TIMEOUT_MS, gapMs: 5, ...options });
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

test("ignores a datagram that is not JSON or has no id", async () => {
	const device = await fake((msg) => ["garbage", `{"src":"no id"}`, `{"id":${msg.id},"result":{"bat_soc":84}}`]);
	expect(await client(device.port).call("ES.GetStatus")).toEqual({ bat_soc: 84 });
	expect(device.seen).toHaveLength(1);
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
	expect(device.seen).toHaveLength(1);
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

test("the next request leaves the gap after the previous reply", async () => {
	const gapMs = 120;
	const device = await fake((msg) => [`{"id":${msg.id},"result":{"n":${msg.id}}}`]);
	const made = client(device.port, { gapMs });
	await Promise.all([made.call("Bat.GetStatus"), made.call("ES.GetStatus")]);
	expect(device.arrived[1] - device.replied[0]).toBeGreaterThanOrEqual(gapMs - TIMER_SLACK_MS);
});

test("a send error reaches the caller as kind network before the timeout", async () => {
	const timeoutMs = 450;
	const made = client(30000, { timeoutMs }, "host.invalid");
	const started = performance.now();
	const failure = await made.call("ES.GetStatus").catch((err: Error) => err);
	expect(failure).toBeInstanceOf(DeviceError);
	expect((failure as DeviceError).kind).toBe("network");
	expect(performance.now() - started).toBeLessThan(timeoutMs);
});

test("close rejects the pending call at once and nothing is sent again", async () => {
	const device = await fake((msg, attempt) => (attempt === 1 ? [] : [`{"id":${msg.id},"result":{"bat_soc":82}}`]));
	const sockets = vi.spyOn(dgram, "createSocket");
	const made = client(device.port);
	const pending = made.call("ES.GetStatus").catch((err: Error) => err);
	await sleep(TIMEOUT_MS / 3);

	made.close();
	const failure = await Promise.race([pending, sleep(0)]);
	expect(failure).toBeInstanceOf(DeviceError);
	expect((failure as DeviceError).kind).toBe("network");

	await sleep(TIMEOUT_MS * 2);
	expect(device.seen).toHaveLength(1);
	expect(sockets).toHaveBeenCalledTimes(1);
});

test("a closed client rejects calls and opens no socket", async () => {
	const device = await fake((msg) => [`{"id":${msg.id},"result":{"bat_soc":80}}`]);
	const made = client(device.port);
	await made.call("ES.GetStatus");
	made.close();

	const sockets = vi.spyOn(dgram, "createSocket");
	const failure = await made.call("ES.GetStatus").catch((err: Error) => err);
	expect(failure).toBeInstanceOf(DeviceError);
	expect((failure as DeviceError).kind).toBe("network");
	expect(sockets).not.toHaveBeenCalled();
	expect(device.seen).toHaveLength(1);
});

test("a socket error rejects the pending call with its cause and the next call opens a new socket", async () => {
	const device = await fake((msg, attempt) => (attempt === 1 ? [] : [`{"id":${msg.id},"result":{"bat_soc":83}}`]));
	const sockets = vi.spyOn(dgram, "createSocket");
	const made = client(device.port);
	const pending = made.call("ES.GetStatus").catch((err: Error) => err);
	await sleep(TIMEOUT_MS / 3);

	const socket: dgram.Socket = sockets.mock.results[0].value;
	socket.emit("error", Object.assign(new Error("recv EHOSTUNREACH"), { code: "EHOSTUNREACH" }));
	const failure = await Promise.race([pending, sleep(0)]);
	expect(failure).toBeInstanceOf(DeviceError);
	expect((failure as DeviceError).kind).toBe("blocked");

	expect(await made.call("ES.GetStatus")).toEqual({ bat_soc: 83 });
	expect(sockets).toHaveBeenCalledTimes(2);
});

test("EHOSTUNREACH maps to kind blocked", () => {
	expect(DeviceError.fromSend(Object.assign(new Error("send EHOSTUNREACH"), { code: "EHOSTUNREACH" })).kind).toBe("blocked");
	expect(DeviceError.fromSend(Object.assign(new Error("send ENETDOWN"), { code: "ENETDOWN" })).kind).toBe("network");
});
