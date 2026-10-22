/// The one place that says where the app's data backend lives.
///
/// A plain `flutter run` uses [defaultApiBaseUrl]. To try another server for
/// one run, override it (optional):
///
///     flutter run --dart-define=TRAVEL_ALERTS_API_BASE_URL=http://127.0.0.1:8080
///
/// An empty override (`--dart-define=TRAVEL_ALERTS_API_BASE_URL=`) turns the
/// backend off and runs on labelled demo data only.
class AppConfig {
  const AppConfig._();

  /// Name of the optional build-time override.
  static const String apiBaseUrlKey = 'TRAVEL_ALERTS_API_BASE_URL';

  /// Public URL of the hosted backend (Render Free web service).
  static const String defaultApiBaseUrl =
      'https://suceava-travel-alerts-api.onrender.com';

  /// The configured URL: the override when given, else [defaultApiBaseUrl].
  /// Compile-time constant lookup, so the key is spelled out literally.
  static const String apiBaseUrl = String.fromEnvironment(
    'TRAVEL_ALERTS_API_BASE_URL',
    defaultValue: defaultApiBaseUrl,
  );
}
