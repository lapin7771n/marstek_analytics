import dgram from "node:dgram";

import { envelope, type JsonObject, ProtocolError, request, resultOf } from "./protocol";

export type DeviceErrorKind = "timeout" | "blocked" | "network" | "protocol";

export class DeviceError extends Error {
	constructor(
		readonly kind: DeviceErrorKind,
		message: string,
	) {
		super(message);
	}

	static fromSend(err: NodeJS.ErrnoException): DeviceError {
		const blocked = err.code === "EHOSTUNREACH" || err.code === "EHOSTDOWN";
		return new DeviceError(blocked ? "blocked" : "network", err.message);
	}
}

export interface Device {
	call(method: string): Promise<JsonObject>;
	close(): void;
}

type Options = { timeoutMs?: number; gapMs?: number };

export class MarstekClient implements Device {
	readonly #timeoutMs: number;
	readonly #gapMs: number;
	#socket?: dgram.Socket;
	#closed = false;
	#abort?: (err: DeviceError) => void;
	#nextId = 1;
	#queue: Promise<void> = Promise.resolve();

	constructor(
		private readonly host: string,
		private readonly port: number,
		options: Options = {},
	) {
		this.#timeoutMs = options.timeoutMs ?? 3000;
		this.#gapMs = options.gapMs ?? 1000;
	}

	call(method: string): Promise<JsonObject> {
		const run = this.#queue.then(() =>
			this.#attempt(method).catch((err: Error) => {
				if (err instanceof DeviceError && err.kind === "timeout") return this.#attempt(method);
				throw err;
			}),
		);
		const pause = () => new Promise<void>((done) => setTimeout(done, this.#gapMs));
		this.#queue = run.then(pause, pause);
		return run;
	}

	close(): void {
		this.#closed = true;
		this.#abort?.(closedError());
		this.#socket?.close();
		this.#socket = undefined;
	}

	#open(): dgram.Socket {
		if (this.#socket !== undefined) return this.#socket;
		const socket = dgram.createSocket("udp4");
		socket.on("error", (err) => {
			if (this.#socket !== socket) return;
			this.#socket = undefined;
			socket.close();
			this.#abort?.(DeviceError.fromSend(err));
		});
		this.#socket = socket;
		return socket;
	}

	#attempt(method: string): Promise<JsonObject> {
		if (this.#closed) return Promise.reject(closedError());
		const socket = this.#open();
		const id = this.#nextId++;

		return new Promise((resolve, reject) => {
			let settled = false;
			const settle = (act: () => void) => {
				if (settled) return;
				settled = true;
				clearTimeout(timer);
				socket.off("message", onMessage);
				this.#abort = undefined;
				act();
			};
			const fail = (err: DeviceError) => settle(() => reject(err));
			const onMessage = (data: Buffer) => {
				try {
					const reply = envelope(data.toString("utf8"));
					if (reply.id !== id) return;
					const result = resultOf(reply.body);
					settle(() => resolve(result));
				} catch (err) {
					fail(new DeviceError("protocol", err instanceof ProtocolError ? err.message : "Bad reply"));
				}
			};
			const timer = setTimeout(() => fail(new DeviceError("timeout", `No reply to ${method}`)), this.#timeoutMs);

			this.#abort = fail;
			socket.on("message", onMessage);
			socket.send(request(id, method), this.port, this.host, (err) => {
				if (err) fail(DeviceError.fromSend(err));
			});
		});
	}
}

function closedError(): DeviceError {
	return new DeviceError("network", "Client is closed");
}
