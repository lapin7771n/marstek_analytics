import { MarstekClient } from "./core/client";
import { formatDuration } from "./core/format";
import { Poller } from "./core/poller";
import { resolve } from "./core/settings";

const settings = resolve({ host: process.env.MARSTEK_HOST, port: process.env.MARSTEK_PORT });

const poller = new Poller({
	connect: () => Promise.resolve({ device: new MarstekClient(settings.host, settings.port), floorPct: settings.floorPct, pollMs: settings.pollMs }),
	now: () => Date.now(),
	publish: ({ estimate, error, message }) => {
		const time = new Date().toISOString().slice(11, 19);
		if (estimate === undefined) return console.log(time, error ?? "waiting", message ?? "");
		console.log(
			time,
			`${estimate.socPct}%`,
			`${Math.round(estimate.batteryAcW)}W`,
			estimate.mode,
			estimate.hours === null ? "—" : formatDuration(estimate.hours),
			error ?? "",
		);
	},
});

poller.start();
