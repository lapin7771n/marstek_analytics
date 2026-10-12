import streamDeck from "@elgato/streamdeck";

import { EtaKey, LevelKey } from "./actions/keys";
import { MarstekClient } from "./core/client";
import { Estimator } from "./core/estimator";
import { Poller } from "./core/poller";
import { resolve, restoreLearned, type Settings } from "./core/settings";

const SAVE_EVERY_MS = 10 * 60_000;

const estimator = new Estimator();
const keys = [new LevelKey(), new EtaKey()];
const inspectors = new Set<string>();

const poller = new Poller({
	estimator,
	now: () => Date.now(),
	connect: async () => {
		const settings = resolve(await streamDeck.settings.getGlobalSettings<Settings>());
		return { device: new MarstekClient(settings.host, settings.port), floorPct: settings.floorPct };
	},
	publish: (snapshot) => {
		if (snapshot.error !== undefined) streamDeck.logger.warn(`poll failed: ${snapshot.error} ${snapshot.message ?? ""}`);
		for (const key of keys) void key.repaint(snapshot);
	},
});

for (const key of keys) {
	key.poller = poller;
	key.onInspector = (context, open) => {
		if (open) {
			inspectors.add(context);
		} else if (inspectors.delete(context) && inspectors.size === 0) {
			void saveLearned();
		}
	};
	streamDeck.actions.registerAction(key);
}

streamDeck.settings.onDidReceiveGlobalSettings<Settings>(() => poller.reconfigure());
streamDeck.system.onSystemDidWakeUp(() => void poller.kick());

await streamDeck.connect();

estimator.restore(restoreLearned(await streamDeck.settings.getGlobalSettings<Settings>()));
poller.start();

setInterval(() => void saveLearned(), SAVE_EVERY_MS);

async function saveLearned(): Promise<void> {
	if (inspectors.size > 0) return;
	const stored = await streamDeck.settings.getGlobalSettings<Settings>();
	if (inspectors.size > 0) return;
	const learned = estimator.learned;
	if (JSON.stringify(stored.learned) === JSON.stringify(learned)) return;
	await streamDeck.settings.setGlobalSettings<Settings>({ ...stored, learned });
}
