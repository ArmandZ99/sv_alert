# Architecture notes

## Status (Phase 1 — foundation and UI)

The app is a Flutter-only client that runs on **explicitly labelled mock data**. There is no backend, login, persistence, live transport integration or push notification delivery. Preferences live in memory and are lost when the app closes.

## Layers (`lib/`)

| Layer | Path | Responsibility |
| --- | --- | --- |
| Domain | `domain/` | Pure Dart models and rules: `TransportService`, `ArrivalStatus`, `DataQuality`, `ServiceFilter`, `DemandOverview`, `NotificationPreferences`. No Flutter UI imports. |
| Data | `data/` | `TransportRepository` interface and `MockTransportRepository`. Real provider adapters will implement the same interface and keep all parsing out of the UI. |
| Presentation | `presentation/` | `ChangeNotifier` controllers (`state/`), theme, Romanian strings (`l10n/`), reusable `widgets/` and `pages/`. |
| Core | `core/clock.dart` | Injectable `Clock` so time-dependent logic and tests are deterministic. |

State management is plain `ChangeNotifier` + `ListenableBuilder`, with no extra packages. The app wires the controllers in `app.dart`; swap the repository there (or pass one to `SuceavaPulseApp`) to change the data source.

## Domain rules worth knowing

- **Status is derived from facts** (`TransportService.statusAt`). Cancelled > actual arrival (arrived) > no estimate (unknown) > estimate already passed without confirmation (unknown) > delay >= 5 min (delayed) > estimate within 15 min (arriving soon) > on time. A schedule-only service is never shown as "on time". These display thresholds live in `StatusRules`; they are separate from the user's notification thresholds.
- **Times**: scheduled, estimated and actual are separate fields. Delay is `estimated/actual - scheduled` and is null when unknown.
- **Service date** is stored per service, and mock ids include the date, so the same number on different days is not conflated.
- **Time zones**: timestamps use the device's local time. Explicit `Europe/Bucharest` handling is not implemented yet and is required before real data and backend alerts.
- **Demand overview** (`DemandOverview`) counts upcoming, non-cancelled arrivals in the next 2 hours (30-minute buckets, per hub). Level uses arrivals in the next hour: below 2 low, below 4 moderate, otherwise high. It does not estimate passengers and says nothing about real ride requests on any platform.
- **Notification preferences** hold the defaults (reminders 30/15/5 min, delay threshold 15 min) in one place. They are not wired to any delivery mechanism.

## Planned boundaries (not built yet)

- **Transport providers:** one adapter per flight, rail or coach source. Each must document authorization, terms of use, refresh limits, actual fields, and whether its times are scheduled or live.
- **Backend worker:** scheduled collection, normalization, source-health monitoring, delay comparison, idempotent notification events, retries and rate limits.
- **Notification delivery:** FCM or equivalent only after real backend processing exists. Local reminders from saved schedules cannot discover new delays while the app is closed.
- **Persistence** of preferences, and migration of `l10n/strings.dart` to `gen_l10n` when English is added.

## Safety and trust

Do not scrape or automate private Bolt systems. Do not imply official affiliation. Keep user location off, avoid suggesting illegal parking or unsafe driving, and clearly label stale, scheduled-only or demo data.
