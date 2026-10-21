# Architecture notes

## Current starter

The current starter is intentionally a Flutter-only UI prototype with in-memory demonstration data. It has no data polling, backend, login, persistence, live transport integration, or push notification delivery.

## Planned boundaries

- **Transport providers:** one adapter per flight, rail, or coach source. Each provider must document authorization, terms of use, refresh limits, actual fields, and whether its times are scheduled or live.
- **Normalized service model:** transport type, public service identifier, full route, Suceava arrival point, service date, scheduled arrival, estimated arrival (nullable), status, source URL, last-updated time, and data quality.
- **Backend worker:** scheduled collection, normalization, source-health monitoring, delay comparison, idempotent notification events, retries, and rate limits.
- **Notification delivery:** FCM or equivalent only after real backend processing is in place. Local reminders based on saved schedules do not independently discover new delays when the app is closed.
- **Demand Radar:** a transparent heuristic based on verified arrivals and time windows only. It must be described as potential demand, not measured Bolt demand or a guarantee of passenger requests.

## Safety and trust

Do not scrape or automate private Bolt systems. Do not imply official affiliation. Keep user location off by default, avoid suggesting illegal parking or unsafe driving, and clearly label stale, scheduled-only, or demo data.
