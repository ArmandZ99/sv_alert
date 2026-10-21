/// Source of "now". Injected so time-dependent logic and tests are deterministic.
typedef Clock = DateTime Function();

DateTime systemClock() => DateTime.now();
