# Outage schedule sources for an iOS app

Checked 2026-10-15. Live requests were plain curl with a browser User-Agent. Facts marked "observed" come from my own requests.

## Summary

- **YASNO** has a public JSON API with no login. It covers Kyiv city and Dnipro. The host is `app.yasno.ua`. The `api.yasno.com.ua` URL from the question returned HTTP 503 in every try.
- **DTEK Dnipro** has an AJAX lookup. It takes a CSRF token and returns the group for an address. The Dnipro and Odesa pages also embed the schedule as JS objects. The Kyiv DTEK pages return an Incapsula challenge to plain clients.
- **No official DTEK or YASNO API** was found.
- **Baskerville42/outage-data-ua** republishes DTEK data as JSON every few minutes. It is MIT and active.

## 1. YASNO

Sources:
- Frontend bundle, which names the API base and the paths: https://static.yasno.ua/outages/assets/index-WYvSLXw6.js
- Public page shell. It redirects from https://yasno.com.ua/schedule-turn-off-electricity to https://static.yasno.ua/kyiv/outages

Base: `https://app.yasno.ua/api/blackout-service/public/shutdowns/`. All routes below are GET, returned 200 JSON, and needed no auth (observed).

| Route | Result |
|---|---|
| `addresses/v2/regions` | Kyiv is id 25 with one DSO, 902. Dnipro is id 3 with DSOs 301 (ДнЕМ) and 303 (ЦЕК). |
| `regions/{regionId}/dsos/{dsoId}/planned-outages` | Object keyed by group, such as "1.1" and "1.2". Each key has `today` and `tomorrow`, each with `date`, `status` and `slots`, plus `updatedOn`. |
| `regions/{r}/dsos/{d}/settings` | `startupModalMessage` as HTML. For Kyiv (25/902) it says the stabilization schedules are not in effect after an accident on the right bank. |
| `probable-outages?regionId=25&dsoId=902` | Weekly template: region, then DSO, then group, then slots keyed by weekday 0 to 6. Each slot is `{start, end, type}`, with minutes from 0 to 1440. Observed type: `NotPlanned`. |
| `addresses/v2/cities`, `streets?regionId&dsoId&cityId&query`, `houses?regionId&dsoId&streetId&query` | Address lookup. Each returns a list of `{id, value}`. |
| `addresses/v2/group?regionId&dsoId&streetId&houseId` | `{"group":19,"subgroup":1}` for Kyiv, Khreshchatyk, house 1 (streetId 1013, houseId 42064). |

Route names come from the bundle, and the lookup chain was confirmed by calls. Also used by https://github.com/aavdberg/ha-yasno/blob/main/custom_components/ha_yasno/api/const.py

Status values from the bundle: `NoOutages`, `ScheduleApplies`, `EmergencyShutdowns`, `WaitingForSchedule`.

State on 2026-10-15 (observed):
- Kyiv (902): every group `EmergencyShutdowns`, slots empty.
- Dnipro (301 and 303): `NoOutages` today, `WaitingForSchedule` tomorrow, slots empty.
- I did not see a populated `ScheduleApplies` payload. The slot shape beyond `{start, end, type}` is UNVERIFIED.

Other points:
- Mapping group 19 subgroup 1 to the key "19.1" in `planned-outages` is UNVERIFIED.
- The ICS route `regions/25/dsos/902/groups/19/subgroups/1/download` returned 500, "There is no file for group Id: 19". Do not use it with that id.
- `https://api.yasno.com.ua/api/v1/pages/home/schedule-turn-off-electricity` returned 503 with `Retry-After: 5`, three times (observed). The path `electricity-outages-schedule` is not in the bundle. Both are UNVERIFIED as working endpoints.
- Bot protection: `app.yasno.ua` sets Incapsula cookies (`visid_incap`, `incap_ses`) and an `x-iinfo` header. My plain requests got no challenge. Behaviour from iOS URLSession is UNVERIFIED.
- The `ha-yasno` author says the login flow rejects plain HTTP clients with 400 and needs a browser TLS fingerprint. Source: https://github.com/aavdberg/ha-yasno/blob/main/custom_components/ha_yasno/api/auth.py
- Account routes use MSAL login at `login.yasno.ua`. Source: same file.

## 2. DTEK

Pages (observed on 2026-10-15):
- `dtek-dnem.com.ua/ua/shutdowns` (Dnipro): 200, about 1.06 MB. Contains inline `DisconSchedule.preset = {...}` and `DisconSchedule.fact = {...}`, a `csrf-token` meta tag, and `ajaxUrl` = `/ua/ajax`. The embedded `fact` was dated 24.07.2026 with empty `data`.
- `dtek-oem.com.ua/ua/shutdowns` (Odesa): 200, about 0.9 MB. Same inline objects. The embedded `fact` was dated 26.01.2026 with empty `data`. Cause UNVERIFIED.
- `dtek-kem.com.ua/ua/shutdowns` (Kyiv city): plain GET returns an Incapsula challenge iframe, not the schedule.
- `dtek-krem.com.ua/ua/shutdowns` (Kyiv oblast): 212 bytes, only an Incapsula resource reference.

Bot protection: Incapsula on all four sites. Kyiv is challenged for plain clients. The `ha-dtek` client raises a rate-limit or WAF error on a challenge. Source: https://github.com/aavdberg/ha-dtek/blob/main/custom_components/dtek/api/client.py

AJAX (Dnipro, observed 2026-10-15):
1. GET the shutdowns page to get session cookies and the `csrf-token` meta value.
2. POST `https://www.dtek-dnem.com.ua/ua/ajax` with header `X-CSRF-TOKEN` and form body `method=...`.
3. `getStreets` returns streets by settlement. Result `true`.
4. `getHomeNum` with `data[0][name]=city`, `data[0][value]=м. Дніпро`, `data[1][name]=street`, `data[1][value]=вул. Генерала Пушкіна`. Result `true`. House `4/Т` came back with `sub_type_reason: ["GPV5.1"]`, which is the group. Start and end were empty, so no outage was active at that moment.
5. `getSchedule` returns `{"result":false,"error":["Unknown method!"]}`. This matches the note that the legacy methods are retired on the Dnipro portal. Source: https://github.com/aavdberg/ha-dtek/blob/main/custom_components/dtek/api/client.py

Method names: https://github.com/aavdberg/ha-dtek/blob/main/custom_components/dtek/api/endpoints.py

Kyiv AJAX calls were not tested, because plain requests get the challenge. UNVERIFIED.

Official API: none found in search. UNVERIFIED that none exists.

## 3. Community projects

| Project | Regions | Access | Licence | Last activity (GitHub API) | Maintained 2026 |
|---|---|---|---|---|---|
| [Baskerville42/outage-data-ua](https://github.com/Baskerville42/outage-data-ua) | Kyiv city (`kyiv`), Kyiv oblast (`kyiv-region`), Dnipro, Odesa | Raw JSON, e.g. `https://raw.githubusercontent.com/Baskerville42/outage-data-ua/main/data/kyiv.json` (307 KB). Parsed from DTEK pages with Playwright in CI. | MIT (LICENSE file). GitHub reports NOASSERTION. | Pushed 2026-10-14. Commits "chore: update schedules and images" every few minutes. Kyiv `lastUpdated` 2026-10-14T22:50Z. | Yes |
| [denysdovhan/ha-yasno-outages](https://github.com/denysdovhan/ha-yasno-outages) | Yasno areas. Kyiv and Dnipro per a DOU roundup, UNVERIFIED from the repo. | Home Assistant integration, uses Yasno plans. Not affiliated with Yasno (README). | MIT | Pushed 2026-10-01. Last commit seen 2026-09-04 (dependency bumps). | Probably yes. 194 stars. |
| [aavdberg/ha-yasno](https://github.com/aavdberg/ha-yasno) | Yasno, same `app.yasno.ua` routes as above | Home Assistant. Schedule routes need no auth. Account routes use login. | MIT | Pushed 2026-09-12 | Probably yes |
| [aavdberg/ha-dtek](https://github.com/aavdberg/ha-dtek) | DTEK. Default `dtek-dnem`. Config also lists `dtek-kem` and `dtek-krem`. | Home Assistant. AJAX with CSRF. Default scan 15 min, allowed 5 to 60 min. | MIT | Pushed 2026-10-09 | Yes |
| [BR0kEN-/ha-dtek-shutdowns](https://github.com/BR0kEN-/ha-dtek-shutdowns) | DTEK | ICS from the DTEK site | none | Archived. Pushed 2026-10-07. | No (archived) |
| [rodion981/ha-energy-outages](https://github.com/rodion981/ha-energy-outages) | Many oblasts via Alerts Energy | Home Assistant. Polls `https://alerts.energy` once per minute per region. No key. | MIT | Pushed 2026-10-13 | Yes |
| [alerts.energy API](https://alerts.energy/api/v1/source-registry/areas/overview) | 26 areas, including Kyiv city (emergency status only, 0 scheduled queues) and oblasts such as Poltava and Cherkasy (24 queues each) | Public JSON, no key, HTTP 200 (observed) | Unknown. Third-party aggregator. | `updated` stamps from 2026-10-14 | Yes |
| [yaroslav2901/OE_OUTAGE_DATA](https://github.com/yaroslav2901/OE_OUTAGE_DATA) | Oblenergo regions (Cherkasy, Chernihiv, Lviv, Kharkiv and others). Kyiv and Dnipro not in the first 12 listed. | JSON and PNG in the repo | none | Last commit 2026-10-14T21:04Z | Yes |
| [chaichuk/svitlo_live](https://github.com/chaichuk/svitlo_live) | Not checked | Home Assistant | MIT | Pushed 2026-03-18 | Unknown |
| [svitlo.live](https://svitlo.live/) | Not checked | Homepage is HTML. No API link in its source. No docs found. | Unknown | Unknown | Unknown |

## 4. Address to group

- **DTEK Dnipro:** the user types the address on the site. An app can do the same through `/ua/ajax` `getHomeNum`, which returns the group in `sub_type_reason`. Source: section 2.
- **YASNO:** the app can resolve an address to a group with public GET routes: city, street, house, then `group`. The user picks the address once, and the app stores the result. Source: section 1.
- **DTEK Kyiv:** not tested. Plain requests are challenged.

## 5. Terms and legal

- **DTEK:** a search found no terms text on scraping or API use. The Dnipro page has no footer link matching privacy, terms or rules (my check). UNVERIFIED.
- **YASNO:** a Visa promotion document names the supplier as ТОВ «КИЇВСЬКІ ЕНЕРГЕТИЧНІ ПОСЛУГИ». Source: https://ua.review.visa.com/dam/VCOM/regional/cemea/ukraine/paywithvisa/promotions/yasno/yasno-terms-conditions.pdf. Its terms of use were not found. UNVERIFIED.
- **Baskerville42 README** says: follow each site's terms. Source: https://github.com/Baskerville42/outage-data-ua
- **Not researched:** Ukrainian copyright or database law, and personal data rules for an app that stores addresses. UNVERIFIED.

## Table

| Source | Covers | Access | Auth / bot protection | Maintained 2026 |
|---|---|---|---|---|
| app.yasno.ua blackout-service API | Kyiv city (25), Dnipro (3: DnEM 301, CEK 303) | Plain HTTPS GET, JSON | No auth. Incapsula cookies, no challenge seen by curl | Yes (updated 2026-10-14/15, observed) |
| api.yasno.com.ua/api/v1/pages/... | Unknown | 503 in all tries | Incapsula `x-iinfo` present | Unknown |
| DTEK Dnipro `/ua/shutdowns` inline + `/ua/ajax` | Dnipro (dtek-dnem) | HTML scrape, POST with CSRF | Incapsula script, no challenge seen by curl | Yes (ajax tested 2026-10-15) |
| DTEK Odesa `/ua/shutdowns` inline | Odesa (dtek-oem) | HTML scrape | Incapsula script. Embedded data stale (26.01.2026) | Unknown |
| DTEK Kyiv `dtek-kem`, `dtek-krem` | Kyiv city, Kyiv oblast | Blocked for plain clients | Incapsula challenge | Unknown |
| Baskerville42/outage-data-ua | Kyiv, Kyiv oblast, Dnipro, Odesa | Raw GitHub JSON | None (public repo) | Yes |
| denysdovhan/ha-yasno-outages | Yasno | Home Assistant | None for schedule | Probably yes |
| aavdberg/ha-yasno | Yasno | Home Assistant | None for schedule. Login for account | Probably yes |
| aavdberg/ha-dtek | DTEK Dnipro, Kyiv, Kyiv oblast | Home Assistant, AJAX | CSRF, WAF handling | Yes |
| BR0kEN-/ha-dtek-shutdowns | DTEK | ICS | None | No (archived) |
| alerts.energy API | Many oblasts, Kyiv city (emergency only) | Public JSON | No key | Yes |
| yaroslav2901/OE_OUTAGE_DATA | Oblenergos | GitHub repo | None | Yes |
| svitlo.live | Unknown | Unknown | Unknown | Unknown |
