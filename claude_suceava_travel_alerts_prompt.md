# Claude Code Prompt --- Suceava Travel Alerts (Flutter)

## Role and objective

Act as a senior Flutter engineer and pragmatic solution architect. Help
me build a production-minded mobile application for **Suceava,
Romania**, that acts as a centralized travel notification panel.

The app should notify users about significant arrivals of: - Flights
arriving at Suceava International Airport (SCV). - Trains arriving at
Suceava railway stations, initially Suceava and optionally Suceava
Nord. - Intercity coaches and buses arriving at relevant bus
stations/stops in Suceava.

The two main use cases are: 1. Notify a user when a tracked service is
expected to arrive in a configurable number of minutes. 2. Notify a user
when a service has a significant delay or its estimated arrival time
changes substantially.

Do not assume every website has an API or that public pages may legally
be scraped. Research and verify the available data access methods,
terms, reliability, rate limits, and permissions before implementing an
integration. Never invent real-time transport data.

## First steps: inspect the repository

Before making changes: 1. Inspect the existing repository, architecture,
Flutter/Dart version, dependencies, navigation, state management, theme,
localization, tests, and Firebase configuration. 2. Reuse existing
conventions and packages where appropriate. Do not replace working
architecture without a clear reason. 3. Report a concise implementation
plan and identify missing configuration/secrets. 4. Then implement the
work in small, testable increments. Do not stop after writing a plan. 5.
If the repository is empty, create a maintainable Flutter project
structure.

## Data sources to investigate

Treat these as candidate sources, not guaranteed API integrations:

### Flights

-   Official Suceava airport website: https://www.aeroportsuceava.ro/ro/
-   Airport flight schedules can be useful for scheduled arrivals, but a
    schedule is not proof of live operational status.
-   Investigate authorized flight-status APIs or official
    airline/airport data for actual delay and estimated-arrival
    information.
-   Store the source, last update time, and whether the time is
    scheduled or estimated.

### Trains

-   CFR Călători: https://www.cfrcalatori.ro/
-   CFR station departures/arrivals:
    https://bilete.cfrcalatori.ro/ro-RO/Stations
-   CFR's "Trenul meu" information:
    https://bilete.cfrcalatori.ro/ro-RO/Itineraries
-   Investigate whether official machine-readable data or an authorized
    integration is available. Do not assume that a human-facing page is
    a supported API.
-   Initially focus on arrivals at Suceava; include Suceava Nord only if
    station coverage and user needs are confirmed.

### Coaches and intercity buses

-   Arrivals in Suceava on Autogari.ro:
    https://www.autogari.ro/Suceava/Sosiri
-   Stations and bus terminals in Suceava:
    https://www.autogari.ro/suceava
-   Investigate official operator feeds, APIs, partner access, or other
    authorized data sources.
-   Timetables alone cannot establish real-time delays. If live arrival
    estimates are unavailable, label the data as scheduled and do not
    send false "live delay" alerts.

For each source, document: - What fields are actually available. -
Whether the data is scheduled, live, estimated, or manually reported. -
How often it can be refreshed. - Access limitations, usage terms, rate
limits, and failure modes. - A fallback when the source is
unavailable. - Whether integration is feasible for an MVP.

If reliable, authorized live data is unavailable for a transport type,
implement a clean provider interface and a clearly marked mock/demo
provider rather than brittle scraping. Explain what is required to
enable production data.

## Product scope

### Main dashboard

Build a clean, modern, mobile-first notification panel with: - A "Next
arrivals" section sorted by estimated arrival time. - Transport type
indicators: flight, train, coach/bus. - Service identifier (flight
number, train number, or operator/service name). - Origin/destination
details as appropriate. - Scheduled arrival time and estimated arrival
time, clearly distinguished. - Delay in minutes, with a clear label and
last-updated timestamp. - A data freshness indicator such as "Updated 2
min ago". - Statuses such as On time, Delayed, Arriving soon, Arrived,
Cancelled, Unknown. - Pull-to-refresh where appropriate. - Loading,
empty, stale-data, offline, and error states. - A visible indication
when only scheduled timetable data is available.

### Filters and service details

-   Filter by flight, train, and coach/bus.
-   Filter or search by service number, operator, or origin.
-   Tap a service to view details, source, planned time, current
    estimate, delay history if available, and last update.
-   Provide a link to the original source when available.
-   Avoid presenting uncertain information as fact.

### Notification preferences

Let users configure: - Arrival reminder thresholds, with defaults of 30,
15, and 5 minutes before arrival. - Significant-delay threshold, with a
default of 15 minutes. - Which transport types to follow. - Optional
selection of specific services, where supported. - Quiet hours /
notification preferences. - Enable/disable notifications globally.

Make thresholds configurable; do not hard-code the defaults throughout
the codebase.

### Notification examples

-   "Train IR 1831 is expected to arrive in Suceava in 15 minutes."
-   "Flight W4 1234 is delayed by 45 minutes. Estimated arrival: 18:40."
-   "Coach to Suceava is expected in 10 minutes."
-   "Updated arrival time: 18:40 (previously 18:10)."

Use Romanian for the initial user-facing UI, with localization structure
that can support English later. Keep notification wording concise and
accessible.

## Important notification behavior

Push notifications for new delays must be generated by a backend or
another reliable background service, not depend on the Flutter app being
open.

Implement logic that: 1. Compares new provider data with the previous
known state. 2. Sends an arrival reminder only when a configured
threshold is crossed. 3. Sends a delay alert only when the delay meets
the user's threshold. 4. Avoids duplicate alerts for the same service,
event, and threshold. 5. Handles changed arrival estimates without
repeatedly notifying for every small fluctuation. 6. Supports
cancellations and major schedule changes when the source provides
reliable status. 7. Marks stale or unavailable data clearly and does not
invent an estimate. 8. Uses idempotent notification/event keys and
records sent notifications. 9. Handles time zones correctly using
Europe/Bucharest and stores timestamps consistently. 10. Considers
service date and overnight arrivals so services with the same number on
different dates are not conflated.

Define a sensible policy for significant ETA changes, for example a
configurable minimum change, and document it. Do not send an alert
merely because a source's formatting changed.

## Suggested architecture

Adapt this to the repository rather than forcing a rewrite.

### Flutter client

-   Flutter / Dart, null safety.
-   Follow the repository's existing state-management and routing
    patterns. If none exist, choose a simple, maintainable option and
    explain why.
-   Separate presentation, domain/business logic, and data access.
-   Typed models for services, status, ETA, source metadata, and
    notification preferences.
-   Repository/provider interfaces so each transport source can be
    implemented and tested independently.
-   Push notification permission flow, token registration, token
    refresh, and notification-tap routing.
-   Secure handling of configuration; no private API keys committed to
    source control.

### Backend

Prefer Firebase if the repository is already configured for it,
otherwise propose a small maintainable backend: - Firebase Cloud
Messaging (FCM) for push delivery. - Cloud Functions or a scheduled
backend worker for source polling and notification evaluation. -
Firestore or an equivalent database for normalized services, user
preferences, source freshness, and sent-notification records. -
Scheduled polling with source-specific intervals that respect source
limitations. - Retries with backoff, timeouts, rate limiting, logs, and
monitoring. - Secrets stored in an appropriate secrets manager, not in
the app or repository. - Validate user preferences and protect
user-specific data with proper access rules. - Do not run one scheduled
polling job per user if a shared provider poll can serve all users.

Remember: local notifications can schedule reminders from already-known
times, but they cannot independently discover a newly announced delay
while the app is closed. Real-time delay alerts require backend
monitoring or a suitable external provider.

## Common normalized data model

Design a typed model with fields appropriate to each transport type,
including at least: - Stable internal service/event ID. - Transport
type. - Provider/source identifier. - Public service identifier (flight
number/train number/operator route). - Origin and destination where
available. - Target Suceava station, terminal, or stop. - Service
date. - Scheduled arrival timestamp. - Estimated arrival timestamp,
nullable if unavailable. - Actual arrival timestamp, nullable. - Delay
in minutes, nullable if unknown. - Status enum. - Data classification:
scheduled / live / estimated / unknown. - Source URL or source reference
where available. - Last fetched/updated timestamp. - Provider's source
timestamp if available.

Keep provider-specific parsing inside provider adapters. Do not leak
HTML parsing or API response structures into widgets.

## MVP delivery phases

### Phase 1 --- Foundation and UI

-   Inspect the repository and document architecture.
-   Build the main dashboard, filters, service details, settings, and
    empty/loading/error states.
-   Add realistic but explicitly marked mock data for flights, trains,
    and buses.
-   Add model and repository interfaces.

### Phase 2 --- Source feasibility and integrations

-   Verify the current official/authorized data access options for each
    transport type.
-   Implement only integrations that are reliable and permitted.
-   Add source freshness and graceful fallback behavior.
-   Keep unavailable integrations behind provider interfaces with
    documented setup steps.

### Phase 3 --- Push notifications

-   Configure FCM and backend scheduled processing.
-   Implement user preferences and threshold-based notification
    evaluation.
-   Prevent duplicates and add notification history.
-   Add Android notification channels and the necessary platform
    configuration; account for iOS if the project targets iOS.

### Phase 4 --- Reliability and release readiness

-   Unit tests for ETA calculations, delay changes, thresholds,
    duplicate suppression, service-date handling, and time zones.
-   Widget tests for dashboard, filters, loading, empty, and stale
    states.
-   Integration tests for repository flows and notification routing
    where feasible.
-   Document Firebase setup, environment variables, secrets, provider
    configuration, and deployment.
-   Run formatter, analyzer, and tests; fix issues introduced by the
    implementation.

## UI and UX expectations

-   Use a polished, practical dashboard inspired by travel boards and
    notification centers.
-   Make arrival time and delay the most visually prominent information.
-   Use accessible contrast, readable typography, and consistent
    spacing.
-   Use color together with text/icons for status; never communicate
    status by color alone.
-   Avoid unnecessary animations and excessive visual complexity.
-   Support small Android screens and handle system insets correctly.
-   Keep the app focused on Suceava rather than building a generic
    national travel app.
-   Do not request location permission unless a concrete feature
    requires it; the initial scope is city-specific.

## Legal, platform, and community considerations
- This is an independent community app unless a formal partnership is established. Make this clear in onboarding/About text and avoid implying that it is developed, endorsed, or operated by Bolt.
- Before any use of Bolt names, logos, APIs, data, or platform-related integrations, review current applicable terms and obtain authorization where needed. Do not scrape, automate, or mine data from the Bolt app/platform.
- Do not try to infer actual Bolt requests or rider identities. Only present transport schedules/status and clearly labeled, approximate demand opportunities based on public arrivals.
- Respect the terms of every transport data provider and any applicable copyright, database, privacy, and consumer-protection requirements.
- Provide a privacy notice if accounts, push tokens, analytics, or other personal data are collected. Collect the minimum required data and secure it appropriately.

## Engineering constraints

-   Do not hard-code sample data as if it were live.
-   Do not claim an integration works until it has been implemented and
    verified.
-   Do not scrape websites in a way that violates their terms, bypasses
    access controls, or overloads the service.
-   Never put API secrets in Flutter code.
-   Avoid excessive dependencies and unnecessary abstractions.
-   Keep error messages useful but do not expose secrets or sensitive
    backend details.
-   Include tests for critical notification logic.
-   If credentials or external access are missing, finish all work that
    can be done, provide a clear configuration checklist, and explain
    exactly what remains blocked.

## Expected result

Work directly in the repository and deliver: 1. A working Flutter
implementation for the completed scope. 2. A clear project/file
structure consistent with the existing codebase. 3. Unit/widget tests
for the critical logic and UI states. 4. A README or implementation
document with architecture and setup instructions. 5. A list of data
sources, their verified capabilities, and known limitations. 6. Exact
Firebase/backend setup and deployment steps if required. 7. A short
summary of files changed, commands/tests run, results, and outstanding
blockers.

Start by inspecting the repository. Then state the plan briefly and
proceed with implementation. Ask me a question only when a decision
genuinely blocks progress; otherwise choose a sensible default and
document it.
