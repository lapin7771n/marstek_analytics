import { type Device, DeviceError } from "./client";
import { estimate } from "./estimator";
import { toEsStatus } from "./protocol";
import { SettingsError } from "./settings";
import type { PollError, Snapshot } from "./views";

const FAILS_BEFORE_ERROR = 3;
const GAP_MS = 1_000;
const NUDGE_MIN_MS = 60_000;

export type PollerDeps = {
	connect(): Promise<{ device: Device; floorPct: number; pollMs: number }>;
	now(): number;
	publish(snapshot: Snapshot): void;
	warn?(message: string): void;
};

export class Poller {
	#device?: Device;
	#timer?: NodeJS.Timeout;
	#running?: Promise<void>;
	#stopped = false;
	#generation = 0;
	#fails = 0;
	#floorPct = 0;
	#pollMs = 60_000;
	#lastCallEnd = Number.NEGATIVE_INFINITY;
	#last: Snapshot = {};

	constructor(private readonly deps: PollerDeps) {}

	get snapshot(): Snapshot {
		return this.#last;
	}

	start(): void {
		this.#stopped = false;
		void this.kick();
	}

	stop(): void {
		this.#stopped = true;
		this.#generation++;
		clearTimeout(this.#timer);
		this.#device?.close();
		this.#device = undefined;
	}

	reconfigure(): void {
		this.#generation++;
		const old = this.#device;
		this.#device = undefined;
		// The firmware still answers the call in flight; close after it.
		void (this.#running ?? Promise.resolve()).then(() => old?.close());
		this.#fails = 0;
		this.#stopped = false;
		void this.kick();
	}

	// Key press and system wake: a request only when the last one ended a minute ago or more.
	nudge(): Promise<void> {
		if (this.deps.now() - this.#lastCallEnd < NUDGE_MIN_MS) return this.#running ?? Promise.resolve();
		return this.kick();
	}

	async kick(): Promise<void> {
		if (this.#running !== undefined) return this.#running;

		clearTimeout(this.#timer);
		const generation = this.#generation;
		this.#running = this.#tick(generation);
		try {
			await this.#running;
		} finally {
			this.#running = undefined;
			if (!this.#stopped) {
				this.#timer = setTimeout(() => void this.kick(), generation === this.#generation ? this.#pollMs : 0);
			}
		}
	}

	async #tick(generation: number): Promise<void> {
		const stale = () => generation !== this.#generation;
		try {
			if (this.#device === undefined) {
				const { device, floorPct, pollMs } = await this.deps.connect();
				if (stale()) {
					device.close();
					return;
				}
				this.#device = device;
				this.#floorPct = floorPct;
				this.#pollMs = pollMs;
				// A new client starts with an empty gap queue; keep the old client's gap.
				const wait = this.#lastCallEnd + GAP_MS - this.deps.now();
				if (wait > 0) await new Promise((done) => setTimeout(done, wait));
				if (stale()) return;
			}
			const device = this.#device;

			const esReply = await device.call("ES.GetStatus").finally(() => {
				this.#lastCallEnd = this.deps.now();
			});
			if (stale()) return;
			const es = toEsStatus(esReply, this.deps.now());
			this.#fails = 0;
			this.#set({ estimate: estimate(es, this.#floorPct) });
		} catch (err) {
			if (stale()) return;
			this.#fails++;
			const error: PollError =
				err instanceof DeviceError ? err.kind : err instanceof SettingsError ? "settings" : "protocol";
			const urgent = error === "settings" || error === "blocked";
			if (urgent || this.#fails >= FAILS_BEFORE_ERROR) {
				this.#set({ ...this.#last, error, message: err instanceof Error ? err.message : "Unknown error" });
			}
		}
	}

	#set(snapshot: Snapshot): void {
		this.#last = snapshot;
		this.deps.publish(snapshot);
	}
}
