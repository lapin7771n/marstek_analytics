import { action, SingletonAction, type WillAppearEvent } from "@elgato/streamdeck";

import { Stabiliser } from "../core/format";
import type { Poller } from "../core/poller";
import { renderKey, toDataUri } from "../core/render";
import { etaHours, etaView, type KeyView, levelView, type Snapshot } from "../core/views";

export abstract class BatteryKey extends SingletonAction {
	poller!: Poller;
	#painted?: string;

	protected abstract view(snapshot: Snapshot): KeyView;

	override async onWillAppear(ev: WillAppearEvent): Promise<void> {
		if (!ev.action.isKey()) return;
		await ev.action.setImage(toDataUri(renderKey(this.view(this.poller.snapshot))));
	}

	override async onKeyDown(): Promise<void> {
		await this.poller.kick();
	}

	async repaint(snapshot: Snapshot): Promise<void> {
		const image = toDataUri(renderKey(this.view(snapshot)));
		if (image === this.#painted) return;
		this.#painted = image;
		for (const instance of this.actions) {
			if (instance.isKey()) await instance.setImage(image);
		}
	}
}

@action({ UUID: "com.mlapin.marstek.level" })
export class LevelKey extends BatteryKey {
	protected view(snapshot: Snapshot): KeyView {
		return levelView(snapshot);
	}
}

@action({ UUID: "com.mlapin.marstek.eta" })
export class EtaKey extends BatteryKey {
	#stable = new Stabiliser();

	protected view(snapshot: Snapshot): KeyView {
		return etaView(snapshot, this.#stable.next(etaHours(snapshot.estimate)));
	}
}
