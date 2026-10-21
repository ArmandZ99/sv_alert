# Architecture notes

## Status (Phase 1 — foundation and UI)

The app is a Flutter-only client that runs on **explicitly labelled mock data**. There is no backend, login, live transport integration or push notification delivery. Notification preferences are saved locally with `shared_preferences` and loaded at startup.

## Structure (`lib/`)

Feature-oriented; each feature keeps its own `domain/` (pure Dart), `data/` and `presentation/` where it has them.

| Folder | Contents |
| --- | --- |
| `app/` | `SuceavaPulseApp` (wiring of controllers) and `AppShell` (bottom navigation). |
| `core/` | `Clock`, `BucharestTime` (all time-zone logic), theme, Romanian strings and formatters, shared widgets (notice banner, loading/message views). |
| `features/transport/` | Shared model: `TransportService`, `TransportType`, `ArrivalStatus`, `DataQuality`; `TransportRepository` + `MockTransportRepository`; status/type styling and `StatusBadge`. |
| `features/arrivals/` | `ServiceFilter` (type + search), `ArrivalsController`, arrivals page, `ArrivalCard`, freshness/stale/error banners, service details sheet. |
| `features/dashboard/` | `DemandOverview` heuristic, dashboard page, `DemandCard`. |
| `features/settings/` | `NotificationPreferences` (+ validated JSON codec), `PreferencesStore` + `SharedPreferencesStore`, `PreferencesController`, settings page. |
| `features/notifications/` | `NotificationEvaluator` (pure alert decisions), `AlertEngine` (evaluator + persistent handled-alert history), `AlertHistoryStore` and its `shared_preferences` implementation. No delivery. |

State management is plain `ChangeNotifier` + `ListenableBuilder`, with no extra packages. The app wires the controllers in `app.dart`; swap the repository there (or pass one to `SuceavaPulseApp`) to change the data source.

## Domain rules worth knowing

- **Status is derived from facts** (`TransportService.statusAt`). Cancelled > actual arrival (arrived) > no estimate (unknown) > estimate already passed without confirmation (unknown) > delay >= 5 min (delayed) > estimate within 15 min (arriving soon) > on time. A schedule-only service is never shown as "on time". These display thresholds live in `StatusRules`; they are separate from the user's notification thresholds.
- **Times**: scheduled, estimated and actual are separate fields. Delay is `estimated/actual - scheduled` and is null when unknown.
- **Service date** is stored per service, and mock ids include the date, so the same number on different days is not conflated.
- **Time zones** (`core/time/bucharest_time.dart`, `timezone` package): every timestamp is an absolute instant (UTC preferred; the system clock returns UTC). Durations such as "minutes until arrival" are differences of instants, so daylight-saving changes cannot distort them (02:45 to 04:30 across the March change is 45 real minutes). Wall-clock questions (quiet hours, service date, display) are answered in `Europe/Bucharest`, never in the device's zone. Source wall-clock times become instants with `fromWallClock`: a time that occurs twice (October) resolves to the first, summer-time occurrence; a time that does not exist (March) is read with the pre-change offset and lands one hour later. A service date is a UTC-midnight `DateTime` whose year/month/day are the Bucharest calendar date.
- **Demand overview** (`DemandOverview`) counts upcoming, non-cancelled arrivals in the next 2 hours (30-minute buckets, per hub). Level uses arrivals in the next hour: below 2 low, below 4 moderate, otherwise high. It does not estimate passengers and says nothing about real ride requests on any platform.
- **Notification preferences** hold the defaults (reminders 30/15/5 min, delay threshold 15 min) in one place. They are persisted (invalid or missing stored fields fall back to defaults one by one) but not wired to any delivery mechanism.
- **Notification decision logic** (`features/notifications/domain/notification_evaluator.dart`) is pure and only *decides*; nothing is sent.
  - *Reminder*: fires when time left <= a threshold; if several are already crossed only the tightest fires and the looser ones are recorded silently.
  - *Delay*: fires once when the delay first reaches the threshold, only from a real estimate (estimated/live data), never from a timetable alone, and never again for later ETA changes.
  - *Never fires* when alerts are off, the type is not followed (or, when specific services are followed, the service is not), the data is stale (>10 min), or the service is cancelled, arrived or past.
  - *Quiet hours* (Bucharest wall clock; start inclusive, end exclusive; start > end crosses midnight; start == end is an empty period, never quiet; disabled never matches). Policy: **arrival reminders are suppressed** (not sent and recorded as handled, so they do not appear when quiet hours end; a later, tighter threshold still fires), because a late reminder is useless. **Delay alerts are deferred** (not sent and not recorded), so the first evaluation after quiet hours sends them if the service is still relevant and still delayed past the threshold. Both are reported in `EvaluationResult.suppressedByQuietHours` / `deferredByQuietHours`.
  - *Idempotency key*: `<service id>|<service date>|<kind>|<threshold>`, e.g. `ir1831|2026-10-21|arrivalReminder|15`. The date is explicit even if the id contains it; the threshold separates reminders; for delays it is the user's delay threshold.
- **Persistent duplicate suppression** (`AlertEngine`): wraps the evaluator with a history of handled keys saved through `AlertHistoryStore` (`shared_preferences`, one JSON object `key -> ISO-8601 UTC`). Keys are recorded when an evaluation returns them, before any delivery, so delivery is at-most-once: a failure can lose an alert but never repeat one. Keys older than 2 days are pruned. If the history cannot be loaded it starts empty (an alert may repeat once); if it cannot be saved, the in-memory history still suppresses duplicates for the session (`lastSaveFailed`). The engine is not yet wired into the UI.

## Planned boundaries (not built yet)

- **Transport providers:** one adapter per flight, rail or coach source. Each must document authorization, terms of use, refresh limits, actual fields, and whether its times are scheduled or live.
- **Backend worker:** scheduled collection, normalization, source-health monitoring, delay comparison, idempotent notification events, retries and rate limits.
- **Notification delivery:** FCM or equivalent only after real backend processing exists. Local reminders from saved schedules cannot discover new delays while the app is closed.
- A delivery layer that consumes `AlertEvent`s (calling `AlertEngine` from the backend or a background worker), plus migration of `l10n/strings.dart` to `gen_l10n` when English is added.

## Safety and trust

Do not scrape or automate private Bolt systems. Do not imply official affiliation. Keep user location off, avoid suggesting illegal parking or unsafe driving, and clearly label stale, scheduled-only or demo data.
