# iOS guide: point to Find battery

Start only after `claude/ios-battery-discovery-91b6ae` (Find battery) and
`claude/ios-first-launch-guide-1374d7` (first-launch guide) are both on `master`.

## Design

`ios/App/GuideSheet.swift` drops from five steps to four:

1. In the Marstek app, open your battery and tap the gear icon at the top right. (`GuideGear`, unchanged)
2. Scroll down and turn on Local API. Leave the port at 30000. (`GuideLocalAPI`, unchanged)
3. Tap Find battery. If it finds nothing, read the IP under Wi‑Fi in the Marstek app. (`GuideIP`)
4. When the app asks to find devices on your local network, tap Allow. (unchanged)

Local API comes before Find battery, because discovery needs it on. The new step keeps the
`GuideIP` screenshot: it shows where to read the IP when discovery finds nothing. So
`ios/Tests/GuideTests.swift` and the asset catalog stay as they are.

Ukrainian for the new key: «Торкніться «Знайти батарею». Якщо нічого не знайдено, подивіться
IP-адресу під «Налаштування Wi‑Fi» у застосунку Marstek.»

## Tasks

- [ ] 1. Rebase this branch on `master` with both features in it.
- [ ] 2. In `GuideSheet.swift`, replace steps 2–5 with steps 2–4 above.
- [ ] 3. In `ios/Shared/Localizable.xcstrings`, add the new key with `uk`; delete
      "Under Wi‑Fi, write down the IP address." and "Enter the IP here and tap Save and check."
- [ ] 4. In `ios/Tests/LocalizationTests.swift`, lower the `strings.count` floor by 1 from its
      post-merge value (one key in, two out).
- [ ] 5. `make test` from `ios/` exits 0.
- [ ] 6. Check the guide on the simulator in English and Ukrainian (`-AppleLanguages (uk)`):
      four steps, three screenshots, text not clipped.
- [ ] 7. Commit `feat: point the ios guide to find battery`; remove this plan before any PR.
