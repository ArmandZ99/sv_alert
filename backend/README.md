# Ingestion backend

A small plain-Dart service that fetches the public transport timetables that may
be used, normalizes them and serves one JSON document to the app. **The app
never fetches, parses or polls the sources itself, and no provider key ever goes
into the Flutter code.** What each source allows is in
[`docs/DATA_SOURCE_FEASIBILITY.md`](../docs/DATA_SOURCE_FEASIBILITY.md).

No Firebase, no database, no push delivery: it keeps its parsed timetables in
memory and refreshes them on a schedule.

## Run

```bash
cd backend
dart pub get
TRAVEL_ALERTS_CONTACT="you@example.org" dart run bin/server.dart
```

`TRAVEL_ALERTS_CONTACT` is **required**: it goes into the `User-Agent`
(`SuceavaTravelAlerts/0.1 (+you@example.org)`) so site owners can reach you.

| Variable | Default | Purpose |
| --- | --- | --- |
| `TRAVEL_ALERTS_CONTACT` | none (required) | Email or URL for the User-Agent. |
| `PORT` | `8080` | Listening port. |
| `HOST` | `127.0.0.1` | Interface. Use `0.0.0.0` only behind a reverse proxy that adds HTTPS. |
| `RAIL_SNTFC_URL`, `RAIL_INTERREGIONAL_URL` | 2025-2026 files on data.gov.ro | Update **every December** (new yearly timetable). |
| `PDFTOTEXT_PATH` | `pdftotext` | The PDF text tool (`poppler-utils` or Xpdf tools). **Needed on the host** for the airport's winter PDF; without it only HTML seasons work and the source status says so. |
| `CORS_ALLOW_ORIGIN` | unset (no CORS headers) | One browser origin allowed to call the API, e.g. `http://127.0.0.1:8081`, only to try the API from the local Swagger UI page. The mobile app does not need it. |
| `AERODATABOX_API_KEY` | unset | Reserved for a future live-flight adapter. Today it only changes the status message; never sent to the app. |

Point the app at it with
`flutter run --dart-define=TRAVEL_ALERTS_API_BASE_URL=https://your-host`
(plain `http://10.0.2.2:8080` is accepted for the Android emulator in debug
builds). Without that setting the app runs on labelled demo data.

## API

The full contract is in [`openapi.yaml`](openapi.yaml) (OpenAPI 3.0.3). Windows (PowerShell) commands to run the backend, test every endpoint, open the spec in Swagger and run the app on an emulator or phone are in [`docs/LOCAL_TESTING.md`](../docs/LOCAL_TESTING.md). Everything there is free and local.

* `GET /v1/arrivals?from=<ISO instant with offset>&to=<...>` services plus the
  status of every source. Default window: 30 min ago to 24 h ahead, at most 72 h.
* `GET /v1/sources` the source statuses only.
* `GET /healthz`.

Every service carries its source name and link, `dataQuality`, `lastUpdated`
(when the backend fetched the source) and `sourceTimestamp` (when the source
publishes one). The `fetchedAt` of the response is the age of the **oldest**
source used. Source status is one of `connected` (live data), `scheduledOnly`,
`unavailable`, `awaitingCredentials`. Today nothing is `connected`.

## How it behaves toward the sources

* Identifies itself and obeys `robots.txt` (missing = allowed; unreadable =
  forbidden) and `Crawl-delay`; waits at least 5 s between requests to a host.
* Caches in memory (6 h for pages, 24 h for the large rail files) and
  revalidates with `ETag` / `If-Modified-Since`.
* Backs off on 429/503 (honours `Retry-After`), treats 401/403 as a block, and
  never solves CAPTCHAs, logs in or works around a refusal.
* Sources are loaded one at a time, so a host is never hit in parallel. One
  failing source never affects the others; a page whose structure changed is
  dropped and reported, not guessed at.
* Requests to the API never trigger fetches on the spot; sources refresh on
  their own schedule (the first request after start waits for the initial load,
  about 30 s because of the politeness delays).

## Adapters (`lib/src/adapters/`)

Everything specific to a provider stays inside its adapter; the rest only sees
`SchedulePattern`s (a recurring arrival and its calendar) and a status.

| Adapter | Source | Notes |
| --- | --- | --- |
| `AirportTimetableAdapter` | aeroportsuceava.ro flight tables (summer, HTML) and the linked arrivals PDFs (other seasons) | Each season keeps its own period, so seasons never mix or duplicate. PDFs are read with `pdftotext` (`AirportPdfTimetableParser`); a failing PDF never takes down a valid season. See the feasibility doc for what the real files contain. |
| `AirportTransferAdapter` | airport "Transfer aeroport" page | Cernăuți - Suceava - Salcea coach shuttle. |
| `TasaAdapter` | tasasuceava.ro/trasee | Operator route page. |
| `RailTimetableAdapter` | data.gov.ro annual timetable XML (OGL-ROU-1.0) | Streams the 12 MB file one train at a time. |
| `UnusedSources` | Tarsin, Autogari.ro, AeroDataBox | Deliberately not read; they appear in the status report with the reason. |

To add a source: write a `SourceAdapter` whose `load` returns an `AdapterLoad`
(patterns, `fetchedAt`, status), throw `FormatException` when the page shape is
not what the parser expects, add fixtures and tests, and list it in
`BackendConfig.buildAdapters`.

## Tests

`test/openapi_test.dart` holds `openapi.yaml` to the truth: it validates the real handler output (including the 400/404/405 bodies), the golden file and the spec's own examples against the schemas, and checks that the enums match the Dart enums. If you change the API, update the spec and the test will tell you where it disagrees.

```bash
dart analyze
dart test
```

Fixtures in `test/fixtures/` are synthetic: they keep each source's real
structure but contain invented values. The end-to-end test serves them from a
fake network at the real URLs and compares the output with
`../test/fixtures/backend_output_v1.json`, which the **app's** tests also parse,
so both sides of the contract are checked against one file. Regenerate it with
`UPDATE_GOLDEN=1 dart test test/end_to_end_test.dart`.

`dart run tool/inspect_sources.dart --airport a.html --tasa t.html --transfer
x.html --rail-xml file.xml` runs the parsers on local copies of the real pages
and prints what they find (no network): use it when a site changes layout.
`--airport-pdf file.pdf` (needs `pdftotext`) and `--airport-pdf-text out.txt`
do the same for the airport's seasonal PDF and list any rows it rejected; run
it on the deployment host to check that its `pdftotext -raw` order matches.

## Deploying (not done yet)

Any host that runs Dart works (a small VM or container). Put it behind a reverse
proxy with HTTPS, keep the process running (systemd or a container restart
policy), and set the variables above. There is no persistence to configure.
