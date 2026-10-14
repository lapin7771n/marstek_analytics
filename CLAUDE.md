# CLAUDE.md

Tools for a Marstek Venus E 3.0 home battery. `streamdeck/` is a Stream Deck plugin
(SDK 3, Node 24, TypeScript) that polls the battery's Open API over UDP on the LAN.
`ios/` is an iPhone app with widgets (SwiftUI, WidgetKit, xcodegen) that reads the same API.

## Commands (run from `streamdeck/`)

`npm run build` · `npm run watch` · `npm run typecheck` · `npm test` ·
`MARSTEK_HOST=192.168.68.50 npm run probe`

From `ios/`: `make test` · `make icon` · `make upload BUILD=<n>`

## Constraints

- The plugin only reads: `ES.GetStatus` every 15 s, `Bat.GetStatus` at most every 5 min (it is suspected to reset some firmwares). The iOS app sends only `ES.GetStatus`. Never send a method that writes.
- The firmware answers one UDP request at a time. Keep one request in flight and the 15 s poll.
- `src/core/` must not import `@elgato/streamdeck`.
- Device facts and the ETA design: `plans/2026-10-12-streamdeck-battery-eta.md`.
