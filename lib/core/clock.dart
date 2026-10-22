/// Source of "now". Injected so time-dependent logic and tests are deterministic.
typedef Clock = DateTime Function();

/// The real current instant, in UTC.
DateTime systemClock() => DateTime.now().toUtc();
