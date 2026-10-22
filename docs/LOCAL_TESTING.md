# Testing everything locally, for free (Windows)

Run the backend and the app on your own PC, look at the API in Swagger, and try
it from an Android emulator or your phone. **No account, no paid service, no
hosting, nothing is deployed.** Everything below runs on `127.0.0.1`.

Commands are for **PowerShell**. The repository is assumed to be at
`C:\Users\Armand\Developer\suceava_travel_alerts`.

What you need: Flutter and Dart (you have them), `adb` (comes with the Android
SDK; already on your PATH), Python (only for the optional Swagger UI page).

## 1. Start the backend

Open **PowerShell window 1** and leave it open (the backend runs in it):

```powershell
cd C:\Users\Armand\Developer\suceava_travel_alerts\backend
dart pub get

# Required: any email or URL. It is sent in the User-Agent so the websites it
# reads can reach you. Nothing is sent anywhere else.
$env:TRAVEL_ALERTS_CONTACT = "your-email@example.com"

# Needed for the airport's WINTER timetable (a PDF). Git for Windows already
# ships a working pdftotext; check the path exists first:
Test-Path "C:\Program Files\Git\ucrt64\bin\pdftotext.exe"
$env:PDFTOTEXT_PATH = "C:\Program Files\Git\ucrt64\bin\pdftotext.exe"

# Optional, only to try the API from the Swagger UI page in section 3:
$env:CORS_ALLOW_ORIGIN = "http://127.0.0.1:8081"

dart run bin/server.dart
```

It prints `Listening on :8080 ...`. Stop it with **Ctrl+C**.

Things to know:

* **The first request waits about 30 seconds.** The backend loads its sources
  on the first request and waits several seconds between requests to the same
  website, on purpose. Later requests answer instantly from memory.
* The first load downloads the two train timetable files from data.gov.ro
  (about 13.8 MB, official open data). The backend keeps them in memory only, so
  **every restart downloads them again.** To avoid that while you restart a lot,
  see "Optional: serve the train files locally" in section 7.
* Without `pdftotext` the backend still works. The winter flights are skipped
  and `/v1/sources` says `pdftotext nu este instalat`. Before 25 October that
  makes no visible difference.
* Without `CORS_ALLOW_ORIGIN` the backend sends no CORS headers (the default,
  and all the mobile app needs). Only Swagger "Try it out" needs it.
* It listens on `127.0.0.1` only, so nothing else on your network can reach it.

## 2. Test each endpoint (PowerShell window 2)

Open a **second** PowerShell window. Keep window 1 running.

```powershell
$base = "http://127.0.0.1:8080"
```

### `GET /healthz`

```powershell
Invoke-RestMethod "$base/healthz"
# ok
# --
# True
```

### `GET /v1/sources` (status of every data source)

```powershell
$s = Invoke-RestMethod "$base/v1/sources" -TimeoutSec 120
$s.sources | Format-Table id, status, serviceCount -AutoSize
$s.sources | Where-Object status -ne 'scheduledOnly' | Format-List id, status, message
```

Expected today: four sources `scheduledOnly` (airport timetable, airport
transfer, TASA, rail), `aerodatabox` = `awaitingCredentials`, `tarsin` and
`autogari-sosiri` = `unavailable` with their reasons. **Nothing is `connected`**
(live).

### `GET /v1/arrivals` (default window: 30 minutes ago to 24 hours ahead)

```powershell
$r = Invoke-RestMethod "$base/v1/arrivals" -TimeoutSec 120
"services: $($r.services.Count)   data fetched at: $($r.fetchedAt)   generated: $($r.generatedAt)"
$r.services | Group-Object type | Format-Table Name, Count -AutoSize
$r.services | Select-Object -First 8 type, serviceNumber, arrivalPoint, scheduledArrival, dataQuality | Format-Table -AutoSize
```

Every service is `scheduled`; `estimatedArrival` and `actualArrival` are empty
and `isCancelled` is `False`. There is no live data.

### `GET /v1/arrivals?from=...&to=...` (your own window)

`from` and `to` need an explicit offset. Using UTC with a `Z` avoids having to
encode a `+`:

```powershell
$fmt  = "yyyy-MM-dd'T'HH':'mm':'ss'Z'"
$inv  = [Globalization.CultureInfo]::InvariantCulture
$from = (Get-Date).ToUniversalTime().ToString($fmt, $inv)
$to   = (Get-Date).ToUniversalTime().AddHours(6).ToString($fmt, $inv)

$w = Invoke-RestMethod "$base/v1/arrivals?from=$from&to=$to" -TimeoutSec 120
"$($w.services.Count) services between $($w.window.from) and $($w.window.to)"
$w.services | Format-Table type, serviceNumber, scheduledArrival -AutoSize
```

With a `+02:00`-style offset the plus sign must be sent as `%2B`:
`...?from=2026-10-26T08:00:00%2B02:00&to=2026-10-26T20:00:00%2B02:00`.

### Errors (use `curl.exe`, which shows the status line)

In PowerShell `curl` is an alias for something else; type **`curl.exe`**.

```powershell
curl.exe -s -i "$base/v1/arrivals?from=yesterday"                      # 400
curl.exe -s -i "$base/v1/arrivals?from=2026-10-21T10:00:00&to=2026-10-21T12:00:00"   # 400, no offset
curl.exe -s -i "$base/v1/arrivals?from=2026-10-01T00:00:00Z&to=2026-10-21T00:00:00Z" # 400, over 72 h
curl.exe -s -i -X POST "$base/v1/arrivals"                             # 405
curl.exe -s -i "$base/nope"                                            # 404
```

### In the browser

These are plain GET requests, so you can just open them (the first one that
needs data may take about 30 seconds):

* <http://127.0.0.1:8080/healthz>
* <http://127.0.0.1:8080/v1/sources>
* <http://127.0.0.1:8080/v1/arrivals>
* <http://127.0.0.1:8080/v1/arrivals?from=2026-10-26T00:00:00Z&to=2026-10-26T12:00:00Z>

## 3. Read and try the API in Swagger (free)

The specification is [`backend/openapi.yaml`](../backend/openapi.yaml)
(OpenAPI 3.0.3). It describes only what the backend really does, and the
backend's tests check it against the real responses.

### Option A: Swagger Editor in the browser (nothing to install)

1. Open <https://editor.swagger.io>.
2. **File → Import file** and choose
   `C:\Users\Armand\Developer\suceava_travel_alerts\backend\openapi.yaml`.
3. The right-hand pane shows the documentation. The editor runs in your browser.

This is enough to **read** the API. **Try it out** from the editor needs the
backend started with `$env:CORS_ALLOW_ORIGIN = "https://editor.swagger.io"` and
a browser that lets an https page call `http://127.0.0.1` (Chrome and Edge do).
This route was not tested here; if it is blocked, use Option B.

### Option B: Swagger UI on your PC (read and try it out)

With the backend running (window 1, with `CORS_ALLOW_ORIGIN` set as in
section 1), open a **third** PowerShell window:

```powershell
cd C:\Users\Armand\Developer\suceava_travel_alerts\backend
python -m http.server 8081 --bind 127.0.0.1
```

Then open <http://127.0.0.1:8081/swagger-ui/>.

Pick an operation, press **Try it out**, then **Execute**. The first call waits
about 30 seconds. The page loads Swagger UI itself (version 5.17.14) from the
jsDelivr CDN, so it needs internet for those two files; the API it calls is your
own backend. Stop with Ctrl+C. (Docker is not installed here, so a Docker route
is not described.)

## 4. Run the Flutter app against the local backend

Without the setting below the app uses clearly labelled demo data. With it, the
app reads real **timetable** data from your backend, and falls back to the demo
data, saying so, if the backend cannot be reached.

The backend URL is passed at build time. **Debug builds only** may use plain
`http` (release builds refuse it by design).

### Android emulator

The emulator reaches your PC's `127.0.0.1` at **`10.0.2.2`**:

```powershell
cd C:\Users\Armand\Developer\suceava_travel_alerts
flutter emulators                      # lists emulators; start one: flutter emulators --launch <id>
flutter devices                        # shows e.g. emulator-5554
flutter run -d emulator-5554 --dart-define=TRAVEL_ALERTS_API_BASE_URL=http://10.0.2.2:8080
```

Base URL for the emulator: **`http://10.0.2.2:8080`**. (Not `127.0.0.1`: inside
the emulator that is the emulator itself. Not `localhost`: same reason.)

### Physical Android phone (USB, recommended)

Requirements:

* USB debugging enabled on the phone, phone connected by cable, and the
  "Allow USB debugging" prompt accepted.
* The backend running on this PC (section 1).
* A **debug** build (`flutter run`), because it talks to the backend over plain
  `http`.

```powershell
adb devices                            # your phone must show as "device" (not "unauthorized")
adb reverse tcp:8080 tcp:8080          # phone's 127.0.0.1:8080 -> this PC's 127.0.0.1:8080
flutter devices                        # note the phone's id
cd C:\Users\Armand\Developer\suceava_travel_alerts
flutter run -d <phone-id> --dart-define=TRAVEL_ALERTS_API_BASE_URL=http://127.0.0.1:8080
```

Base URL for a phone over USB: **`http://127.0.0.1:8080`**. Why this works:
`adb reverse` makes the phone's own `127.0.0.1:8080` reach your PC's backend
through the cable, so the backend stays on loopback, **no firewall change and no
Wi-Fi setup are needed**. The mapping disappears when the cable is unplugged or
adb restarts: run `adb reverse` again. Remove it with
`adb reverse --remove tcp:8080`.

**Over Wi-Fi (not supported as is).** A phone on the same Wi-Fi could in theory
use your PC's LAN address, but the app **rejects plain `http` to anything except
`localhost`, `127.0.0.1` and `10.0.2.2`**, and the backend listens on loopback
only. So a LAN address like `http://192.168.x.x:8080` is refused on purpose.
Wi-Fi testing would need an `https` URL, which is outside this free local setup.

### What you should see in the app

* **Panou / Sosiri:** real timetable services with the banner
  **"Orar programat, nu timp real"**; each card says **Programat**, never on
  time or delayed, and shows its source.
* **Setări → Surse de date:** each source with the status and message from your
  backend (nothing "Conectat (timp real)").
* If the backend is not running or not reachable: **"Date reale indisponibile"**
  and the demo data, every card tagged **DATE DEMO**.

## 5. Run the automated tests

```powershell
cd C:\Users\Armand\Developer\suceava_travel_alerts\backend
dart analyze
dart test

cd C:\Users\Armand\Developer\suceava_travel_alerts
flutter analyze
flutter test
```

## 6. Troubleshooting

| Symptom | Cause and fix |
| --- | --- |
| `Configuration error: Set TRAVEL_ALERTS_CONTACT ...` | Set `$env:TRAVEL_ALERTS_CONTACT` in the same window before `dart run`. |
| First request is slow | Normal: about 30 s on the first request after start. |
| `/v1/sources` says `pdftotext nu este instalat` | Set `$env:PDFTOTEXT_PATH` (section 1) and restart the backend. |
| Port already in use | Another process uses 8080: `$env:PORT = "8090"` and use that port in every URL (and in `adb reverse`). |
| Swagger "Try it out" says "Failed to fetch" | Backend not started with a matching `CORS_ALLOW_ORIGIN` (`http://127.0.0.1:8081` for Option B), or it is still on its first, slow load. |
| `curl` prints an HTML/odd result | You typed `curl`, which is a PowerShell alias; use `curl.exe`. |
| App shows "Date reale indisponibile" | Backend not running, wrong URL for the device (emulator `10.0.2.2`, USB phone `127.0.0.1` with `adb reverse`), or a release build (cleartext refused). |
| `adb devices` shows `unauthorized` | Unlock the phone and accept the USB debugging prompt, then run `adb devices` again. |
| Banner says the URL was ignored | The URL must be `https`, or `http` only for localhost/10.0.2.2, with no credentials or query string. |

## 7. Optional: serve the train files locally

Avoids re-downloading the 13.8 MB train files on every backend restart. Do it
once, then point the backend at the copies. (The files are the official open
data on data.gov.ro; see `docs/DATA_SOURCE_FEASIBILITY.md`.)

```powershell
mkdir C:\temp\rail -Force | Out-Null
cd C:\temp\rail
Invoke-WebRequest "https://data.gov.ro/dataset/c4f71dbb-de39-49b2-b697-5b60a5f299a2/resource/0f67143e-bb88-4a06-8e7a-b35b1eb91329/download/trenuri-2025-2026_sntfc.xml" -OutFile sntfc.xml
Start-Sleep -Seconds 12      # data.gov.ro asks for a 10 s delay between requests
Invoke-WebRequest "https://data.gov.ro/dataset/b4e2ce0b-6935-44b1-8e9d-f3999123358a/resource/1a083cf5-d37c-4618-aeb8-3f1ba0dd22dc/download/trenuri-2025-2026_interregional-calatori.xml" -OutFile interregional.xml
python -m http.server 8099 --bind 127.0.0.1      # leave this window open
```

Then, in backend window 1, before `dart run`:

```powershell
$env:RAIL_SNTFC_URL = "http://127.0.0.1:8099/sntfc.xml"
$env:RAIL_INTERREGIONAL_URL = "http://127.0.0.1:8099/interregional.xml"
```

The timetable is valid until 12 December 2026; after that these URLs (and the
official ones) change.

## 8. Cleaning up

Press **Ctrl+C** in each window. `adb reverse --remove tcp:8080` removes the
phone mapping. Nothing was installed or paid for, and no files outside this
repository were created (except `C:\temp\rail` if you used section 7).
