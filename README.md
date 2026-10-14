# Marstek Analytics

A Stream Deck plugin for the Marstek Venus E 3.0 home battery. It reads the battery over your LAN and shows two keys:

- **Battery level:** charge percent and current power (`+` while charging).
- **ETA:** time until full while charging, time until empty while discharging. While idle on the grid it shows `IF OUTAGE`: how long the battery would carry the backup-socket load.

The plugin only reads. It sends `ES.GetStatus` and `Bat.GetStatus` and never a command that changes the battery.

## Requirements

- Stream Deck 7.1 or later on macOS 12+ or Windows 10+
- Node 24
- Open API enabled for the battery in the Marstek app (UDP port 30000 by default)
- A fixed LAN address for the battery. The firmware ignores discovery, so you type the IP into the key settings.

## Install from source

```bash
cd streamdeck
npm install
npm run build
npx streamdeck link com.mlapin.marstek.sdPlugin
```

Restart Stream Deck, drag **Battery level** and **ETA** from the Marstek Battery category, and enter the battery IP in the key settings. The floor setting is the charge percent the battery keeps in reserve (12 % by default); the ETA counts down to it.

## Check the connection

```bash
cd streamdeck
MARSTEK_HOST=192.168.1.50 npm run probe
```

It prints a line every 15 s with the percent and watts. They should match the Marstek app.

## How the ETA works

The estimator forecasts load from a 1-minute and a 15-minute average, so a kettle barely moves a 10-hour estimate. It learns the charge and discharge efficiency and the slow-down above 90 % from the battery's own counters and keeps them in the plugin settings. Details: [plans/2026-10-12-streamdeck-battery-eta.md](plans/2026-10-12-streamdeck-battery-eta.md).

## Development

Run from `streamdeck/`: `npm test`, `npm run typecheck`, `npm run watch` (rebuilds and restarts the plugin on save).
