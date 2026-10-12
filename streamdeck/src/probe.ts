import { MarstekClient } from "./core/client";
import { Estimator } from "./core/estimator";
import { formatDuration } from "./core/format";
import { Poller } from "./core/poller";
import { resolve } from "./core/settings";

const settings = resolve({ host: process.env.MARSTEK_HOST, port: process.env.MARSTEK_PORT });
const estimator = new Estimator();

const show = (hours: number | null) => (hours === null ? "—" : formatDuration(hours));

const poller = new Poller({
	connect: () => Promise.resolve({ device: new MarstekClient(settings.host, settings.port), floorPct: settings.floorPct }),
	now: () => Date.now(),
	estimator,
	publish: ({ estimate, tempC, error, message }) => {
		const time = new Date().toISOString().slice(11, 19);
		if (estimate === undefined) return console.log(time, error ?? "waiting", message ?? "");
		console.log(
			time,
			`${estimate.socPct}%`,
			`${Math.round(estimate.batteryAcW)}W`,
			estimate.mode,
			`full ${show(estimate.toFullH)}`,
			`${estimate.projected ? "if-outage" : "empty"} ${show(estimate.toEmptyH)}`,
			`${tempC ?? "?"}C`,
			error ?? "",
			JSON.stringify(estimator.learned),
		);
	},
});

poller.start();
