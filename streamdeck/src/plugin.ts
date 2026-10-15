import streamDeck from "@elgato/streamdeck";

import { EtaKey, LevelKey } from "./actions/keys";
import { MarstekClient } from "./core/client";
import { Poller } from "./core/poller";
import { resolve, type Settings } from "./core/settings";

const keys = [new LevelKey(), new EtaKey()];

const poller = new Poller({
	now: () => Date.now(),
	connect: async () => {
		const settings = resolve(await streamDeck.settings.getGlobalSettings<Settings>());
		return { device: new MarstekClient(settings.host, settings.port), floorPct: settings.floorPct };
	},
	publish: (snapshot) => {
		if (snapshot.error !== undefined) streamDeck.logger.warn(`poll failed: ${snapshot.error} ${snapshot.message ?? ""}`);
		for (const key of keys) void key.repaint(snapshot);
	},
	warn: (message) => streamDeck.logger.warn(message),
});

for (const key of keys) {
	key.poller = poller;
	streamDeck.actions.registerAction(key);
}

streamDeck.settings.onDidReceiveGlobalSettings<Settings>(() => poller.reconfigure());
streamDeck.system.onSystemDidWakeUp(() => void poller.kick());

await streamDeck.connect();

poller.start();
