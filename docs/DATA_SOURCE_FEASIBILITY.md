# Data sources: feasibility and what is implemented

Research dates: **2026-10-21** (feasibility) and the same day for the implementation checks below. Method: reading each official public page, its published terms and `robots.txt`, and vendor pricing pages; for the implemented sources, running the real parsers on the live pages and on the official files. Pages and terms can change without notice (CFR §25, Autogari §14.2), so re-check before relying on them.

**Bottom line.** Three of the four sources that publish openly are now read by a small backend and reach the app as real, **timetable-only** data: **flights** (airport timetable: HTML for the summer season, the linked PDF for winter), **trains** (official open-licence annual timetable) and **coaches** (TASA and the airport's Cernăuți shuttle). A live run on 2026-10-21 produced **96 real services in 24 h (76 trains, 11 coaches, 9 flights)**. None of it is live: there are no estimates, delays or cancellations anywhere, and every service says so. No live source is connected, and the alert engine is not connected to any of this data.

Legend: ✔ confirmed · ? not verified · ✘ not provided.

## What works now

| Type | Source | Status | Times | Real services in the live run | Main limitation |
| --- | --- | --- | --- | --- | --- |
| Flights | Airport timetable: HTML tables (summer) + linked arrivals PDF (winter) | **scheduled-only** | Scheduled | 9 (summer, 21 Oct); winter from 25 Oct | Winter comes from a PDF read with `pdftotext` (must be installed). One transposed pair of rows in the source PDF is rejected. No reuse permission confirmed. |
| Trains | data.gov.ro annual timetable XML, OGL-ROU-1.0 (CFR Călători + Interregional Călători files) | **scheduled-only** | Scheduled | 76 | No delays. Other operators' files not integrated. Holiday rules ignored. Files must be re-pointed every December. |
| Coaches | TASA route page (`tasasuceava.ro/trasee`) | **scheduled-only** | Scheduled | 4 | Operating days and validity not published (assumed daily). Few arrivals published. |
| Coaches | Airport "Transfer aeroport" page (Cernăuți shuttle) | **scheduled-only** | Scheduled | 7 | No validity end; operator per trip not stated. No reuse permission confirmed. |
| Coaches | Tarsin | **unavailable** | none | 0 | Timetable only in a JavaScript app; its internal API is not used. |
| Coaches | Autogari.ro | **unavailable** (not used) | none | 0 | Terms §8.1 forbid copying without written consent. |
| Flights | AeroDataBox (live) | **awaiting credentials** | n/a | 0 | Not implemented; needs an account, then a check of SCV coverage and fields. |
| Trains | CFR/Infofer "Trenul meu" (live delay) | awaiting permission | n/a | 0 | Website only, no documented API. |

"Status" is the value the backend reports per source: `connected`, `scheduledOnly`, `unavailable` or `awaitingCredentials`. Nothing is `connected`. Nothing is called verified: for the airport and TASA pages there is no explicit reuse licence, so permission is **unconfirmed** (see "Needs you").

## Fields actually available, per source

| Field | Airport timetable | Rail XML | TASA | Airport transfer |
| --- | --- | --- | --- | --- |
| Service identifier | ✔ flight number | ✔ category + number (e.g. IR 1831) | ✔ `TASA <origin> – <destination>` | ✔ direction + route label |
| Operator | ✔ airline | ✔ per file (CFR Călători / Interregional) | ✔ TASA | ✔ both operators named, trip not assigned |
| Full route / intermediate stops | origin only (direct flights) | ✔ origin, commercial stops, destination | ✔ only where the operator lists stops (the București direction lists none) | ✔ every station of the table |
| Exact arrival point in Suceava | ✔ Aeroportul Suceava (SCV) | ✔ Gara Suceava / Suceava Nord / Suceava Vest | ✔ Autogara Nouă TASA | ✔ Autogara Suceava, or the airport (Salcea) |
| Scheduled arrival | ✔ (local, `(+1)` handled) | ✔ (seconds after operating-day midnight) | ✔ | ✔ |
| Estimated / actual arrival | ✘ | ✘ | ✘ | ✘ |
| Delay | ✘ | ✘ | ✘ | ✘ |
| Cancellation | ✘ | ✘ | ✘ | ✘ |
| Validity period | ✔ from the page heading | ✔ from the file header (14 Dec 2025 - 12 Dec 2026) | ✘ | ✘ |
| Source timestamp | ✘ | ✔ export date (3 Dec 2025) | ✘ | ✘ |

Every service also records its **source name and link**, a `dataQuality` of `scheduled`, and `lastUpdated` (when the backend fetched the source). The response's `fetchedAt` is the age of the oldest source used.

## Source by source

### Flights: airport timetable (summer HTML tables + winter PDF)
- Page: [flight schedule](https://aeroportsuceava.ro/ro/2016-01-29-10-35-08). `robots.txt` disallows only Joomla internals (not `/images/`), so the page and its PDFs are allowed.

**What the raw HTTP response contains** (re-fetched and counted on 2026-10-21; 109,266 bytes, identical to the first fetch, not a search-engine rendering):
- **14 tables: 7 departures and 7 arrivals (one per weekday), all for the summer period 29 March - 24 October 2026.** There are **no winter rows in the HTML.**
- The winter period "25 OCTOMBRIE 2026 - 27 MARTIE 2027" appears four times, but only as the **text of links** to the winter departures/arrivals PDFs. The same goes for the summer PDFs. The table heading itself states the summer period.
- So the question "are winter arrivals in the HTML or only in PDFs" has a definite answer: **only in the linked PDF.** (The page's `Last-Modified` header is the request time, not a content date.)

**The winter arrivals PDF** (`ORAR_SOSIRI_ZBORURI_REGULATE_OCTOMBRIE_2026_MARTIE_2027_2.pdf`, 251,180 bytes, `Last-Modified` 20 Oct 2026): public, no login, not restricted by `robots.txt`; downloaded once with your approval and read locally.
- It is a **text PDF** (3 pages, 63 flight rows), not a scan. Text extraction works with `pdftotext -raw -enc UTF-8` (Xpdf 4.06 here): rows come out one per line, with correct diacritics and the date-limit remarks right after their row. The default and `-layout` modes **misalign** the cells (they are vertically centred in tall rows), so they must not be used. Poppler's `pdftotext -raw` order has not been tested; check it with `dart run tool/inspect_sources.dart --airport-pdf <file>` on the deployment host.
- Format: `<day> <number> <airline> [aircraft] <origin> Suceava (SCV) <dep> <arr>[ (+1)]`. 16 of the 63 rows carry a dated remark, in exactly two forms: "Începând din dd.mm.yyyy" and "Operează până pe dd.mm.yyyy". Every such date falls on the weekday of its row, which shows the dates are **inclusive** first/last operating days.
- Assumptions, as for the HTML tables: the day is the operating (departure) day, the arrival time is Suceava time ("ORE LOCALE" in the footer), `(+1)` is the next calendar day.
- **The PDF contains an error.** In the Thursday block, W4 3648 (London) is printed with 21:50 -> 23:00 and RO 809 (Bucharest) with 20:25 -> 01:35 (+1), the opposite of every other day (London takes 5 h 10, Bucharest 1 h 10). I confirmed with the text coordinates that this is what the document shows, not an artefact of extraction. The parser rejects rows whose duration differs by more than 25 minutes from their origin's usual one (only for origins with at least 3 rows) and reports them in the source status. **Result: the Thursday W4 3648 and RO 809 arrivals are missing rather than wrong.** Worth telling the airport.
- Cross-checks done: every flight number present in both seasons has the same origin; each origin has one stable duration across all its other rows; the real file gives 63 rows, 30 patterns after merging weekdays, and exactly those 2 rejected rows.

**How the adapter handles the seasons** (`AirportTimetableAdapter`):
- The HTML tables are parsed with the period named in the heading above them (never one taken from a link's text). The page's arrivals PDF links are discovered (same host, https, "SOSIRI" in the text, period in the text); departures PDFs and other hosts are ignored.
- A linked PDF is read only if its season is not over, starts within 60 days, and **does not overlap the season already in the tables**. So when the airport later puts the winter timetable into the HTML tables, the winter PDF and the ended summer PDF are not fetched and nothing is duplicated.
- Each season keeps its own period, so a service date belongs to exactly one season: summer services end with Saturday 24 Oct (a Saturday `(+1)` arrival at 01:35 on the 25th is still the summer service), winter services start with Sunday 25 Oct. A PDF whose own period differs from its link is ignored.
- **Failures are local.** If the winter PDF cannot be fetched, extracted or parsed, the valid summer timetable is still served and the status says why; once the summer period is over and the PDF is unusable, the source is `unavailable` with the reason. The source is reported `unavailable` only when **no published season covers today or later** (verified: at 21 Oct and 26 Oct it is `scheduledOnly`; at 30 Mar 2027, after 27 Mar, it is `unavailable`, naming 27.03.2027 as the last end).
- All times stay `scheduled`; nothing is estimated, and the alert engine is not connected.

**Requirements and limits**
- The backend host needs the `pdftotext` command (`poppler-utils` or Xpdf tools); override its path with `PDFTOTEXT_PATH`. Without it the PDF season is skipped with the message "pdftotext nu este instalat" and only HTML seasons work.
- The PDF is fetched at most once a day (`If-Modified-Since`/`ETag` revalidation), the page every 6 hours.
- If the airport changes the PDF layout, the parser rejects the file (unknown structure or unreadable rows) and says so; it never guesses. The airport footer warns that the program may change at the operator's decision, so a published time can still be wrong.
- Terms: none published for the page or the PDFs; footer "Toate drepturile rezervate". **Reading the PDF has the same unconfirmed reuse status as the HTML tables;** nothing here establishes a right to republish them.

### Trains: official annual timetable (open licence)
- Datasets: [CFR Călători (SNTFC) 2025-2026](https://data.gov.ro/dataset/mers-tren-sntfc-cfr-calatori-s-a) (11.9 MB) and [Interregional Călători 2025-2026](https://data.gov.ro/dataset/mers-tren-interregional-calatori) (1.9 MB). Dataset pages state licence **OGL-ROU-1.0**, publisher S.C. Informatică Feroviară S.A. on data.gov.ro (timetable published by C.F.R. S.A.), "static reference information, not real-time". I did not read the licence text itself, only the licence named on the dataset pages.
- Verified in the files (downloaded once, with your approval, and checked): header validity **14 Dec 2025 to 12 Dec 2026**, export 3 Dec 2025; 1,256 and 216 trains; **all three stations present**: Suceava (code 51607), Suceava Nord (51645), Suceava Vest (54439).
- How the XML is read is **inferred from the data** (the schema file is not published with it): per-leg `OraS` is the arrival in seconds after midnight; the stop type of a station sits on the leg that leaves it (`C` commercial, `A` long reversal dwell, `N` no stop, `T` technical). Cross-check: with this rule Suceava Vest gets exactly 4 trains, matching the 4 a public station page lists. For Suceava and Suceava Nord that page lists more (84 and 51) than the two files give (56 and 32); the likely reason is other operators' files (Regio Călători and others, not integrated), but that is an inference, not verified.
- Days of operation: bits 0-6 of `Zile` are read as Monday to Sunday (consistent patterns such as 31 = Mon-Fri, 352 = Sat+Sun, 368 = Fri-Sun). Higher bits (probably public holidays) are undocumented and ignored, so holiday-day services can be wrong. Calendar entries of an unknown type are skipped and counted.
- Station names are tidied (cedillas to comma-below, operational suffixes such as "Hm." dropped). Trains are shown with the real route, but arrival is at each Suceava station separately.
- The timetable is static: it will not show delays, cancellations or replacement services.
- The dataset URLs contain yearly ids. After the second Saturday of December the status becomes `unavailable` ("timetable expired") until `RAIL_SNTFC_URL` / `RAIL_INTERREGIONAL_URL` are updated.

### Coaches: TASA
- Page: [trasee](https://www.tasasuceava.ro/trasee/). `robots.txt` disallows only `/wp-admin/`. No terms-of-use page is linked from the site (footer has GDPR, complaints, ANPC).
- Produced: the three published arrivals from București (17:45, 19:00, 23:30 at Autogara Nouă TASA) and the 06:50 Botoșani - Târgu Mureș service that passes through Suceava. Not produced: departures from Suceava (not arrivals) and the Târgu Mureș - Botoșani direction (no Suceava time is published).
- The page shows the seven weekday letters identically for every route and no validity period, so services are **assumed daily**; the app's source status says so.

### Coaches: airport transfer page (Cernăuți - Suceava - airport)
- Page: [transfer aeroport](https://www.aeroportsuceava.ro/ro/info-pasageri/transfer-aeroport). Same `robots.txt` as above; same "all rights reserved" footer.
- Produced: arrivals at the Suceava bus station (08:50, 12:30, 16:50, 20:30) and at the airport (09:30, 17:30), with every table station as the route. The text says the service runs daily with two operators; it does not say which operator runs which trip, and gives no validity end.

### Tarsin (not used)
- `robots.txt` disallows `/administrator/`, `/agentie/`, `/monitor/`, `/pasageri/`; the route pages are allowed but are a ~9 KB JavaScript shell that contains **no timetable**. The timetable is fetched by the page's own scripts from an internal API. Calling an undocumented internal API is not a published page, so it is **not done**. The terms page was not reviewed. Needs an agreement or a feed.

### Autogari.ro (not used)
- Terms [§8.1](https://www.autogari.ro/Termeni): content may not be reproduced, copied or exploited commercially without prior written consent; §8.2-8.3: content and its structure are under copyright. No API or licence offered. Not requested, parsed or republished.

### Flights, live: AeroDataBox (not implemented)
- Docs and pricing as previously confirmed: free Basic tier 400 units/month, non-commercial, attribution required; paid tiers from about $8/month; no resale on any plan. **Unverified**: SCV coverage, whether arrivals carry estimated/actual times, and units per call. The adapter slot exists and reports `awaitingCredentials`; a key set on the server does not enable anything yet.

### Trains, live: CFR/Infofer "Trenul meu" (not used)
- The website shows real-time progress and delay per train, but there is no documented API and the terms are silent on automated access, which is not permission. Needs a written agreement with CFR Călători / ARF.

## How the pipeline is built

See [`backend/README.md`](../backend/README.md). In short: one adapter per source behind a common interface; a polite fetcher (identifying User-Agent, robots.txt, Crawl-delay, minimum 5 s between requests to a host, ETag/If-Modified-Since, back-off on 429/503, block on 401/403, no CAPTCHA or login handling); sources loaded one at a time so a failure stays local; a page whose structure changed is dropped and reported; the last good timetable is kept if a refresh fails and the status says so. The app receives one normalized JSON contract and validates it strictly (explicit UTC offsets, no estimate on scheduled data).

**Live check on 2026-10-21:** starting the backend against the four public pages (rail files served locally) returned HTTP 200 with 96 services and 7 source statuses; the app's parser accepted all 96 with none rejected. The first request took about 28 s because of the politeness delays; later requests read memory.

## In the app

- Demo data remains an explicit fallback: used when no backend URL is configured or the backend cannot be reached. Every demo service carries a "DATE DEMO" tag, and a list that mixes real and demo services is labelled per service.
- Real timetable data is labelled "Orar programat, nu timp real" and every card shows its status as "Programat", never on time, delayed or arriving soon.
- Settings shows each source with the status the backend reports and its message.
- Timetable-only data is flagged stale only after 36 hours (live data after 10 minutes).

## Alerts

The alert engine is **not connected** to this data. It would never raise a delay alert from it (a test enforces this), and its arrival reminders on timetable data are marked as timetable-based. Before connecting it, decide per source what freshness and what "on time" can honestly mean: for timetable-only sources an arrival reminder is a promise about a schedule, not about the vehicle.

## Needs you

1. **Airport permission (flights and shuttle).** Both airport pages, and the winter PDF, are read without an explicit reuse licence. Ask the airport (contact page: [aeroportsuceava.ro/ro/contact/informatii](https://aeroportsuceava.ro/ro/contact/informatii)) for written permission to use the timetable data in a community app, and ask them to correct the transposed Thursday W4 3648 / RO 809 times in the winter PDF. Ask whether they can publish the timetable as a feed or in the page itself.
2. **TASA permission (optional but advisable).** No terms are published; ask them to confirm use and, ideally, to publish operating days.
3. **Rail files.** Say whether to also integrate other operators' yearly files (Regio Călători, Softrans and others on data.gov.ro): each needs a download approval from you, and the dataset URLs must be updated every December.
4. **A host for the backend** (a small VM or container with HTTPS, with `pdftotext` installed) and a contact email for its User-Agent. Then build the app with `--dart-define=TRAVEL_ALERTS_API_BASE_URL=https://...`.
5. **Live data, if wanted:** an AeroDataBox account (never put the key in chat or the repo) and a decision whether the app counts as commercial; a written agreement with CFR Călători / ARF for live train delays; written consent from BILETERIA SRL (Autogari.ro) or operator feeds for more coaches; an agreement with Tarsin.
