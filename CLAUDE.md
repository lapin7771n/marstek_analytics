# CLAUDE.md

Tools for a Marstek Venus E 3.0 home battery. `streamdeck/` is a Stream Deck plugin
(SDK 3, Node 24, TypeScript) that polls the battery's Open API over UDP on the LAN.
`ios/` is an iPhone app with widgets (SwiftUI, WidgetKit, xcodegen) that reads the same API.

## Commands (run from `streamdeck/`)

`npm run build` · `npm run watch` · `npm run typecheck` · `npm test` ·
`MARSTEK_HOST=192.168.68.50 npm run probe`

From `ios/`: `make test` · `make icon` · `make upload BUILD=<n>`

## Constraints

- The plugin sends only `ES.GetStatus`, every 15 s, like the iOS app. Never send a method that writes. `Bat.GetStatus` is suspected to reset some firmwares, so do not add it back.
- The firmware answers one UDP request at a time. Keep one request in flight and the 15 s poll.
- `src/core/` must not import `@elgato/streamdeck`.
- The ETA formula is `QuickEstimate` in `ios/Shared/Estimate.swift`. `src/core/estimator.ts` ports it; keep the two in step.

## Git flow

- One branch per task, cut from master: `git switch -c <type>/<slug> --no-track origin/master`. `<type>` is the Conventional Commit type of the work: `feat`, `fix`, `docs`, `chore`, `refactor`, `test`, `build`.
- A session in an app worktree starts on `claude/<slug>`. Rename it before the first push: `git branch -m <type>/<slug>`.
- When the gate passes, push and open the PR to `master` without asking: `git push -u origin <branch>`, then `gh pr create --base master`. Before the PR, remove this branch's plan file and put a screenshot of the change in the PR body.
- Never merge. After `gh pr create`, run `/land-pr`: it waits for the owner's merge, then deletes the branch.
