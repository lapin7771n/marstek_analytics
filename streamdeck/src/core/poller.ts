import { type Device, DeviceError } from "./client";
import type { Estimator } from "./estimator";
import { toBatStatus, toEsStatus } from "./protocol";
import { SettingsError } from "./settings";
import type { PollError, Snapshot } from "./views";

const TICK_MS = 15_000;
const BACKOFF_MS = 60_000;
const BAT_EVERY_MS = 300_000;
const BAT_RETRY_MS = 60_000;
const ES_GAP_MS = 120_000;
const FAILS_BEFORE_ERROR = 3;

export type PollerDeps = {
	connect(): Promise<{ device: Device; floorPct: number }>;
	now(): number;
	publish(snapshot: Snapshot): void;
	estimator: Estimator;
	warn?(message: string): void;
};

export class Poller {
	#device?: Device;
	#timer?: NodeJS.Timeout;
	#running?: Promise<void>;
	#stopped = false;
	#generation = 0;
	#fails = 0;
	#batTriedAt = Number.NEGATIVE_INFINITY;
	#batFailed = false;
	#esAt = Number.NEGATIVE_INFINITY;
	#tempC?: number;
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
		this.#device?.close();
		this.#device = undefined;
		this.#fails = 0;
		this.#batTriedAt = Number.NEGATIVE_INFINITY;
		this.#esAt = Number.NEGATIVE_INFINITY;
		this.#stopped = false;
		void this.kick();
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
				const backoff = this.#fails >= FAILS_BEFORE_ERROR ? BACKOFF_MS : TICK_MS;
				this.#timer = setTimeout(() => void this.kick(), generation === this.#generation ? backoff : 0);
			}
		}
	}

	async #tick(generation: number): Promise<void> {
		const stale = () => generation !== this.#generation;
		try {
			if (this.#device === undefined) {
				const { device, floorPct } = await this.deps.connect();
				if (stale()) {
					device.close();
					return;
				}
				this.#device = device;
				this.deps.estimator.floorPct = floorPct;
			}
			const device = this.#device;

			const now = this.deps.now();
			const batWaitMs = this.#batFailed ? BAT_RETRY_MS : BAT_EVERY_MS;
			const gap = now - this.#esAt > ES_GAP_MS && this.#batTriedAt <= this.#esAt;
			if (now - this.#batTriedAt >= batWaitMs || gap) {
				this.#batTriedAt = now;
				try {
					const reply = await device.call("Bat.GetStatus");
					if (stale()) return;
					const bat = toBatStatus(reply, this.deps.now());
					this.deps.estimator.battery(bat);
					this.#tempC = bat.tempC;
					this.#batFailed = false;
				} catch (err) {
					if (stale()) return;
					this.#batFailed = true;
					this.deps.warn?.(`Bat.GetStatus failed: ${err instanceof Error ? err.message : "Unknown error"}`);
				}
			}
			const reply = await device.call("ES.GetStatus");
			if (stale()) return;
			const es = toEsStatus(reply, this.deps.now());

			this.#fails = 0;
			this.#esAt = es.t;
			this.#set({ estimate: this.deps.estimator.sample(es), tempC: this.#tempC });
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
