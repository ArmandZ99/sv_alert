# Architecture notes

## Status (Phase 1 — foundation and UI)

The app is a Flutter-only client that runs on **explicitly labelled mock data**. There is no backend, login, live transport integration or push notification delivery. Notification preferences are saved locally with `shared_preferences` and loaded at startup.

## Structure (`lib/`)

Feature-oriented; each feature keeps its own `domain/` (pure Dart), `data/` and `presentation/` where it has them.

| Folder | Contents |
| --- | --- |
| `app/` | `SuceavaPulseApp` (wiring of controllers) and `AppShell` (bottom navigation). |
| `core/` | `Clock`, theme, Romanian strings and formatters, shared widgets (notice banner, loading/message views). |
| `features/transport/` | Shared model: `TransportService`, `TransportType`, `ArrivalStatus`, `DataQuality`; `TransportRepository` + `MockTransportRepository`; status/type styling and `StatusBadge`. |
| `features/arrivals/` | `ServiceFilter` (type + search), `ArrivalsController`, arrivals page, `ArrivalCard`, freshness/stale/error banners, service details sheet. |
| `features/dashboard/` | `DemandOverview` heuristic, dashboard page, `DemandCard`. |
| `features/settings/` | `NotificationPreferences` (+ validated JSON codec), `PreferencesStore` + `SharedPreferencesStore`, `PreferencesController`, settings page. |
| `features/notifications/` | `NotificationEvaluator`: pure alert decision logic (no delivery). |

State management is plain `ChangeNotifier` + `ListenableBuilder`, with no extra packages. The app wires the controllers in `app.dart`; swap the repository there (or pass one to `SuceavaPulseApp`) to change the data source.

## Domain rules worth knowing

- **Status is derived from facts** (`TransportService.statusAt`). Cancelled > actual arrival (arrived) > no estimate (unknown) > estimate already passed without confirmation (unknown) > delay >= 5 min (delayed) > estimate within 15 min (arriving soon) > on time. A schedule-only service is never shown as "on time". These display thresholds live in `StatusRules`; they are separate from the user's notification thresholds.
- **Times**: scheduled, estimated and actual are separate fields. Delay is `estimated/actual - scheduled` and is null when unknown.
- **Service date** is stored per service, and mock ids include the date, so the same number on different days is not conflated.
- **Time zones**: timestamps use the device's local time. Explicit `Europe/Bucharest` handling is not implemented yet and is required before real data and backend alerts.
- **Demand overview** (`DemandOverview`) counts upcoming, non-cancelled arrivals in the next 2 hours (30-minute buckets, per hub). Level uses arrivals in the next hour: below 2 low, below 4 moderate, otherwise high. It does not estimate passengers and says nothing about real ride requests on any platform.
- **Notification preferences** hold the defaults (reminders 30/15/5 min, delay threshold 15 min) in one place. They are persisted (invalid or missing stored fields fall back to defaults one by one) but not wired to any delivery mechanism.
- **Notification decision logic** (`features/notifications/domain/notification_evaluator.dart`) is pure and only *decides*; nothing is sent. Reminder: fires when time left <= a threshold; if several are already crossed only the tightest fires and the looser ones are recorded silently. Delay: fires once when the delay first reaches the threshold, only from a real estimate (estimated/live data), never from a timetable alone, and never again for later ETA changes. Nothing fires when alerts are off, the type is not followed (or, when specific services are followed, the service is not), the data is stale (>10 min), or the service is cancelled, arrived or past. Idempotency keys are `serviceId|kind|threshold`; the caller stores `keysToRecord` and passes them back as `alreadyHandled`. Quiet hours are left to the delivery layer.

## Planned boundaries (not built yet)

- **Transport providers:** one adapter per flight, rail or coach source. Each must document authorization, terms of use, refresh limits, actual fields, and whether its times are scheduled or live.
- **Backend worker:** scheduled collection, normalization, source-health monitoring, delay comparison, idempotent notification events, retries and rate limits.
- **Notification delivery:** FCM or equivalent only after real backend processing exists. Local reminders from saved schedules cannot discover new delays while the app is closed.
- **Persisting handled alert keys** and a delivery layer that consumes `AlertEvent`s, plus migration of `l10n/strings.dart` to `gen_l10n` when English is added.

## Safety and trust

Do not scrape or automate private Bolt systems. Do not imply official affiliation. Keep user location off, avoid suggesting illegal parking or unsafe driving, and clearly label stale, scheduled-only or demo data.
