import { type Device, DeviceError } from "./client";
import type { Estimator } from "./estimator";
import { toBatStatus, toEsStatus } from "./protocol";
import { SettingsError } from "./settings";
import type { PollError, Snapshot } from "./views";

const TICK_MS = 15_000;
const BACKOFF_MS = 60_000;
const BAT_EVERY = 2;
const FAILS_BEFORE_ERROR = 3;

export type PollerDeps = {
	connect(): Promise<{ device: Device; floorPct: number }>;
	now(): number;
	publish(snapshot: Snapshot): void;
	estimator: Estimator;
};

export class Poller {
	#device?: Device;
	#timer?: NodeJS.Timeout;
	#running?: Promise<void>;
	#stopped = false;
	#ticks = 0;
	#fails = 0;
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
		clearTimeout(this.#timer);
		this.#device?.close();
		this.#device = undefined;
	}

	reconfigure(): void {
		this.#device?.close();
		this.#device = undefined;
		this.#fails = 0;
		this.#stopped = false;
		void this.kick();
	}

	async kick(): Promise<void> {
		if (this.#running !== undefined) return this.#running;

		clearTimeout(this.#timer);
		this.#running = this.#tick();
		try {
			await this.#running;
		} finally {
			this.#running = undefined;
			if (!this.#stopped) {
				const delay = this.#fails >= FAILS_BEFORE_ERROR ? BACKOFF_MS : TICK_MS;
				this.#timer = setTimeout(() => void this.kick(), delay);
			}
		}
	}

	async #tick(): Promise<void> {
		try {
			if (this.#device === undefined) {
				const { device, floorPct } = await this.deps.connect();
				this.#device = device;
				this.deps.estimator.floorPct = floorPct;
			}
			const device = this.#device;

			if (this.#ticks++ % BAT_EVERY === 0) {
				const bat = toBatStatus(await device.call("Bat.GetStatus"), this.deps.now());
				this.deps.estimator.battery(bat);
				this.#tempC = bat.tempC;
			}
			const es = toEsStatus(await device.call("ES.GetStatus"), this.deps.now());

			this.#fails = 0;
			this.#set({ estimate: this.deps.estimator.sample(es), tempC: this.#tempC });
		} catch (err) {
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
