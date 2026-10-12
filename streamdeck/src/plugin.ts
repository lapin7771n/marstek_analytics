import streamDeck, { action, SingletonAction, type WillAppearEvent } from "@elgato/streamdeck";
import dgram from "node:dgram";

const HOST = "192.168.68.50";
const PORT = 30000;

function readSoc(): Promise<string> {
	return new Promise((resolve) => {
		const socket = dgram.createSocket("udp4");
		const done = (text: string) => {
			clearTimeout(timer);
			socket.close();
			resolve(text);
		};
		const timer = setTimeout(() => done("timeout"), 3000);
		socket.on("error", (err) => done(err.message));
		socket.on("message", (data) => {
			const match = /"bat_soc":\s*(\d+)/.exec(data.toString("utf8"));
			done(match ? `${match[1]}%` : "no soc");
		});
		socket.send(JSON.stringify({ id: 1, method: "ES.GetStatus", params: { id: 0 } }), PORT, HOST, (err) => {
			if (err) done(err.message);
		});
	});
}

@action({ UUID: "com.mlapin.marstek.level" })
class LevelKey extends SingletonAction {
	override async onWillAppear(ev: WillAppearEvent): Promise<void> {
		if (!ev.action.isKey()) return;
		await ev.action.setTitle(await readSoc());
	}
}

streamDeck.actions.registerAction(new LevelKey());
await streamDeck.connect();

streamDeck.logger.info(`skeleton read: ${await readSoc()}`);
