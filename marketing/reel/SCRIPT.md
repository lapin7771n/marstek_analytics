# Battery ETA reel

1080×1920, 60 fps, 38.3 s, sound off works: every line is burned in. One direction. Ukrainian only. The video ends on the call to action and holds it.

## Brief

- **Remember:** the Marstek app does not show how much time is left; Battery ETA does, and says whether the battery lasts until the power returns.
- **Viewer action:** find Battery ETA in the App Store (text call, no badge). Link in the caption: https://apps.apple.com/ua/app/id6822926943
- **Unacceptable:** a claim the app does not meet; a superlative; an English word other than Battery ETA, YASNO, Wi‑Fi, Marstek, Marstek Venus E 3.0, App Store; the Marstek app's UI, name as a screen, or logo; a number other than `58 %`, `−620 Вт`, `3 год 30 хв` and the two verdict lines; the YASNO warning for any city but Kyiv; Apple's badge; the Golden Delta mark, font or gold; bounce or elastic motion; a crossfade between scenes; a flat 2D-only scene; text under 37 px.

## Assets

| Asset | Source |
| --- | --- |
| Gauge ring, liquid light, glow, dust (3D) | `blender/ring.py`, Cycles on the PC, one continuous shot |
| App icon | `ios/App/icon.svg`, copied to `public/brand/battery-eta-icon.svg` |
| Palette | `ios/Shared/Faces.swift`: bg `#0F0F12`, good `#3DDC97`, warn `#FFB547`, bad `#FF6B5E` |
| App strings | `ios/Shared/Localizable.xcstrings` (uk), verbatim |
| Glass panels | drawn in Remotion from the app's layouts, demo data only |
| Font | Onest, `@fontsource-variable/onest`, OFL |
| Music and effects | synthesized in `scripts/music.py` and `scripts/sound.py`, no third-party audio |

## Beats

| # | Time | On screen | Copy | Viewer learns |
| --- | --- | --- | --- | --- |
| 1 | 0.0–4.0 | Dark glass ring floats in a blackout | Чи вистачить батареї Marstek до кінця відключення? | Where the question comes from: a blackout, a Marstek battery |
| 2 | 4.0–9.7 | Ring fills to 58 %, cold and dim, percent only | Застосунок Marstek не показує, скільки часу лишилося | Percent alone does not say how long the battery lasts |
| 3 | 9.7–15.4 | Ring lights up green; panel with ДО РОЗРЯДУ and 3 год 30 хв as the largest thing in the frame | Battery ETA показує | Battery ETA gives the time left |
| 4 | 15.4–21.1 | Panel: ВИСТАЧИТЬ, Вистачить до 18:00, запас 1 год 20 хв | Вкажіть, коли дадуть світло | It answers against the time the grid returns |
| 5 | 21.1–26.9 | Ring and room go red; panel with the red-flagged line | А якщо не вистачить? | It says when the battery runs out and by how much |
| 6 | 26.9–32.6 | Ring green again; panel: Вимкніть потужні прилади, YASNO · лише Київ | Попередить до відключення | It warns before an outage and says what to do (Kyiv only) |
| 7 | 32.6–38.3 | Icon in the ring, Battery ETA, call, compatibility line | Battery ETA / Шукайте в App Store / для Marstek Venus E 3.0 | Where to get it, and which battery it fits |

## Holds

Hold = `0.8 + 0.3 × words`, plus 1.0 s when the ring changes state. Words are every word and number visible once the beat settles, panel text included. The hold starts when the last element has settled (0.6 s after the cut; 0.85 s for beat 2; 1.25 s for the CTA) and ends 0.3 s before the exit. Scene lengths snap up to the beat grid (105 bpm). `src/reel/timeline.test.ts` fails if any actual hold is shorter than required.

| beat | words | required hold | actual hold |
| --- | --- | --- | --- |
| hook | 7 | 2.90 s | 3.10 s |
| problem | 9 | 4.50 s | 4.56 s |
| answer | 9 | 4.50 s | 4.81 s |
| verdict | 13 | 4.70 s | 4.81 s |
| tension | 10 | 4.80 s | 4.81 s |
| action | 9 | 4.50 s | 4.81 s |
| cta | 11 | 4.10 s | 4.46 s |
