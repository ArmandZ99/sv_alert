# Data source feasibility — Phase 2

Research date: **2026-10-21**. Method: reading the official public pages, their published terms and `robots.txt`, and vendor pricing pages. **No data was scraped, downloaded or extracted, and no account was created or API called.** Pages and terms can change without notice (CFR §25, Autogari §14.2), so re-check before building.

**Bottom line:** no real source can be integrated today without something only you can provide (an account, or written permission). Nothing is `verified`. The app therefore still runs on explicit mock data, and the Settings screen now says so.

Legend: ✔ confirmed on an official page · ? not verified · ✘ not provided by the source.

Integration status values: **verified** (authorized, implemented, checked against real responses) · **awaiting credentials** · **awaiting permission** · **awaiting verification** (an addition: looks usable, but origin or coverage is unconfirmed) · **unavailable**.

## Summary

| Type | Best candidate | Times it can give | Status | What unblocks it |
| --- | --- | --- | --- | --- |
| Flights | AeroDataBox API (via a backend) | Scheduled; estimated/actual **?** | awaiting credentials | Your account, then a check of SCV coverage and fields |
| Flights | Airport's published timetable | Scheduled only | awaiting permission | Written OK from the airport to reuse it programmatically |
| Trains | CFR/Infofer "Trenul meu" (real-time delay) | Live delay ✔ on the website; no API | awaiting permission | Written agreement with CFR Călători / ARF |
| Trains | Open-licence timetable (GTFS) | Scheduled only | awaiting verification | Confirm official origin, Suceava / Suceava Nord coverage and download rights |
| Coaches | Autogari.ro arrivals page | Scheduled only | awaiting permission | Written consent from BILETERIA SRL (terms §8.1) |
| Coaches | Direct operator feeds | Unknown | unavailable (none found) | Agreements with each operator serving Suceava |

## 1. Flights — Suceava Airport (SCV)

### 1a. Official airport website — `aeroportsuceava.ro`
- Links: [home](https://www.aeroportsuceava.ro/ro/), [flight schedule page](https://aeroportsuceava.ro/ro/2016-01-29-10-35-08), [contact](https://aeroportsuceava.ro/ro/contact/informatii).
- ✔ Publishes seasonal **arrival and departure timetables** (29 Mar–24 Oct 2026 and 25 Oct 2026–27 Mar 2027) as embedded tables and PDFs.
- ✔ **No live board:** no estimated or actual times, delays or cancellations on the page.
- ✔ **No API, feed or open-data page** is mentioned or linked.
- ✔ **No terms of use** found; the footer says "Toate drepturile rezervate" (all rights reserved). Absence of terms is not permission to reuse.
- Fields: service id ✔ (e.g. TAROM RO 809/810, Wizz Air W4/W6), route ✔ (origin/destination airports), Suceava arrival point ✔ (SCV), scheduled arrival ✔, estimated ✘, actual ✘, delay ✘, cancellation ✘.
- Nature: **scheduled**, seasonal. Refresh: when the airport republishes (twice a year).
- Status: **awaiting permission** (to parse or mirror). Practical use: a reference to cross-check a live provider, or a schedule-only fallback if the airport agrees.

### 1b. AeroDataBox (candidate live provider)
- Links: [docs](https://doc.aerodatabox.com/), [pricing](https://aerodatabox.com/pricing).
- ✔ Offered through API.Market, RapidAPI, or directly. ✔ Pricing page lists a free **Basic** tier (400 API units/month, 1 request/s, **commercial use not allowed, attribution required**) and paid tiers: Pro $7.50 (API.Market) or $8 (RapidAPI) for 5,000 units; Ultra $37.50–$40 for 50,000; direct plans from $19/month. Commercial use allowed on paid tiers. **Reselling data is not allowed on any plan.** Paid plans have longer caching rights.
- ✔ A FIDS (airport departures/arrivals) page-size limit is listed for Basic (12 hours), which suggests the airport board endpoint is available.
- ✔ The vendor says coverage is "extensive but not worldwide".
- **?** Not verified (the field-level docs were not readable here): whether SCV is covered, whether arrivals carry estimated/revised and actual times, the status values, how many "units" one airport call costs, and how fresh estimates are. Treat live estimates as **unknown** until a real response from SCV is inspected.
- Credentials: an API key. **It must live on a backend, never in the Flutter app.**
- Status: **awaiting credentials**.

### 1c. Other flight APIs (not preferred)
- **aviationstack** ([pricing](https://aviationstack.com/product)): ✔ Free plan 100 requests/month, non-commercial; paid from $49.99/month; status updates delayed 30–60 s. ? Airport arrivals fields and SCV coverage unverified. Fallback only.
- **FlightAware AeroAPI:** third-party sources disagree on its free tier, so nothing is confirmed. ? Not assessed further.
- OpenSky (ADS-B positions) gives aircraft positions, not scheduled/estimated arrivals per airport, so it is not a fit.

## 2. Trains — Suceava and Suceava Nord

### 2a. CFR Călători / Infofer "Trenul meu"
- Links: [Trains page](https://bilete.cfrcalatori.ro/ro-RO/Trains), [terms](https://bilete.cfrcalatori.ro/ro-RO/Home/TermsConditions), [CFR Călători](https://www.cfrcalatori.ro/).
- ✔ The public website lets a person look up a train (`/ro-RO/Tren/{number}`) and see stop times and **real-time progress including delay**. News reports say a real-time position map (with delays) launched on the ARF Infofer platform in November 2024; positions for CFR trains are approximated from the train-guidance system (reported, not verified by me).
- ✔ **This is website functionality, not a documented API.** No API, open-data or developer page was found.
- ✔ The terms (reviewed) are **silent** on automated access, copying and API use. Silence is not authorization. §22 refers to separate contracts for "authorized distributors". §25: terms change without notice. `www.cfrcalatori.ro/robots.txt` allows all crawlers, but that file covers the marketing site, not the ticketing host, and robots.txt is not permission.
- Fields: train number ✔, stop times ✔, delay ✔ (on the website), cancellation **?**, full route **?**, arrival at Suceava vs Suceava Nord **?** (not confirmed for either station), actual arrival **?**. Field names and update rate of any machine-readable form are unknown.
- Nature: **live (website only)**. Refresh rate and rate limits: unknown.
- Status: **awaiting permission**. Contact: the terms (§19) list `bileteonline@cfrcalatori.ro` for questions; ARF / Informatică Feroviară (infrastructure data) are the other party to ask.

### 2b. Open-licence national timetable (GTFS)
- Link: [MobilityDatabase entry mdb-3236](https://mobilitydatabase.org/feeds/gtfs/mdb-3236).
- ✔ The entry describes a GTFS feed built from Informatică Feroviară open data, licence **OGL-ROU-1.0** (the Romanian open government licence), valid 14 Dec 2025–12 Dec 2026. ✔ It is hosted by a third party (a converter), not by the railway.
- **?** Not verified: that the official publisher offers this data (e.g. on data.gov.ro), that CFR Călători services and the Suceava / Suceava Nord stops are present, and the right to fetch it from the third-party host. I did **not** download it.
- Nature: **scheduled only**: no delays, no live arrival. Cannot support delay alerts.
- Status: **awaiting verification**. Needs your OK to download and inspect one file (see next steps).

## 3. Coaches and intercity buses

### 3a. Autogari.ro
- Links: [arrivals in Suceava](https://www.autogari.ro/Suceava/Sosiri), [Suceava page](https://www.autogari.ro/suceava), [terms](https://www.autogari.ro/Termeni), [about](https://www.autogari.ro/Despre), [contact](https://www.autogari.ro/Contact).
- ✔ Operated by BILETERIA SRL, which states it is a schedule-information site and **not a transport company**.
- ✔ The arrivals page lists a clock time, an operator and a chain of stops. It shows **no delay or status**, so it is a **timetable**. It does not name the Suceava arrival point in the part I read. The page text exceeds what I read (the last ~55,000 characters were not examined).
- ✔ **Terms:** §8.1 — content may not be reproduced, copied or exploited commercially without the administrator's **prior written consent**; §8.2–8.3 — content, including its systems and structure, is under copyright and needs the rights holders' permission. The terms do not mention bots or an API. ✔ Access is monitored (§5.3.2(d)). `robots.txt` disallows a list of dynamic paths (routes, checkout and several `.php` endpoints).
- ✔ No API or data licence is offered. Operators can register via a "Înscriere transportator" form and the REZMax console, which suggests data comes from operators; the source of the schedule is not stated.
- Status: **awaiting permission**. Reading the page as a person is fine; **extracting or republishing its data needs written consent.**

### 3b. Direct operator integrations
- Operators named on the page (e.g. Lilian Express, Family SRL, Euro Tip) are only names seen on a listing. No operator API, feed or contact channel was found, and live arrival estimates for coaches were not found anywhere.
- Status: **unavailable** until an operator agrees to share data. Coaches stay in scope: they remain demo data until a permitted source exists.

## MVP recommendation

1. **Ship what is true.** Keep the demo-labelled app. The in-app notice and "Surse de date" card now state that no real source is connected.
2. **Flights first (lowest barrier).** Create an AeroDataBox account (via API.Market or RapidAPI), use the playground to request SCV arrivals for a week, and compare them with the airport PDF timetable and real flights. Check for estimated/revised and actual times, cancellations and update behaviour. Then decide the plan: the free tier forbids commercial use; ask the vendor whether a free community app qualifies. Calls must go through a small backend that holds the key and polls on a schedule.
3. **Trains: ask, in parallel.** Write to CFR Călători (and ARF / Informatică Feroviară) requesting authorized programmatic access to arrival and delay data for Suceava and Suceava Nord. Meanwhile, with your OK, verify the open GTFS timetable as a **scheduled-only** fallback.
4. **Coaches: ask for consent.** Write to BILETERIA SRL for written consent or a feed, and to the main operators serving Suceava. Until then coaches stay demo; do not scrape.
5. **Mixed state is the realistic MVP:** flights near-live, trains scheduled (or live if CFR agrees), coaches demo. Every card must show its own source and whether the time is scheduled or estimated.

Cost rough order (unverified, from vendor pages): AeroDataBox Pro about $8/month for 5,000 units. At one call every 10 minutes (~4,300 calls/month) it fits only if a call costs one unit, which is **not confirmed**.

## Integration boundary (what exists now)

- **Existing contract:** `TransportRepository.fetchUpcomingArrivals()` returns a `TransportSnapshot` of normalized `TransportService`s. The UI, the filters and the (still unconnected) `AlertEngine` depend only on that.
- **Adapters never run in the app.** Provider keys, HTML/PDF/vendor-JSON parsing and polling belong on a backend. The app receives one normalized JSON document, parsed by `NormalizedArrivalsParser` (`features/transport/data/sources/`). Its rules, covered by tests on synthetic fixtures (`test/fixtures/normalized_arrivals_v1.json`):
  - every timestamp needs an explicit offset (`Z` or `+02:00`) and is converted to UTC; a naive "18:40" is rejected;
  - an estimated/actual time is rejected unless `dataQuality` is `estimated` or `live`, so a timetable can never appear as a live estimate;
  - `fetchedAt` and each `lastUpdated` are required, so freshness is known;
  - invalid services are rejected with a reason (not silently dropped); a malformed or unsupported payload becomes a safe `TransportFetchException`.
- **Mapping wall-clock source times:** when a backend adapter reads "18:40" from a Romanian source it must use `BucharestTime.fromWallClock` (it handles the March gap and October overlap), then emit UTC.
- **Config:** `ProviderConfig` accepts only a backend base URL, passed with `--dart-define=TRAVEL_ALERTS_API_BASE_URL=...`. It rejects credentials, query strings (where keys hide), fragments and plain http (except localhost / `10.0.2.2`), and never echoes the value in errors. Absent = mock only. **No provider key belongs in Flutter code or the repository.**
- **Catalog:** `DataSourceCatalog` records each candidate with its honest status. Update it and this document together.
- **Not built:** the HTTP client, the backend, and the wiring of `ProviderConfig` into app startup. They need a backend that does not exist yet, so nothing real is connected and nothing was faked.

### Before the first real source goes live
1. Make the demo banner **per-service**: today `ArrivalsController.isMock` is true only when the snapshot is mock, so a mixed list (some real, some demo) would be mislabelled. Show the mock banner and badges based on the services actually shown.
2. Add a `RemoteTransportRepository` that calls the backend and uses the parser.
3. **Do not connect `AlertEngine` to a provider** until, for that provider, you know: what `lastUpdated` vs `sourceTimestamp` mean, how often it refreshes, how stale is too stale (the evaluator's 10-minute default may not fit), and that its "estimated" fields really are estimates. The evaluator already ignores timetable-only data for delay alerts and never reports schedule-only services as live.

## Actions that need you

1. **Flights:** create an AeroDataBox account (API.Market or RapidAPI), and tell me the plan you pick. Do not paste the key into chat or the repo; it will go into the backend's secret store.
2. **Trains:** send the access request to CFR Călători / ARF (draft available on request). Tell me if I may download and inspect the open GTFS timetable.
3. **Coaches:** send the written-consent request to BILETERIA SRL and identify which operators serve Suceava.
4. **Decision:** is the app free, ad-free and community-run, or could it count as commercial? It decides which provider tiers you may use.
