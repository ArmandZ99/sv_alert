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

  /// Public URL of the hosted backend. Replace the placeholder with the address
  /// Render shows for the web service after a successful deploy.
  static const String defaultApiBaseUrl =
      'https://REPLACE_AFTER_RENDER_DEPLOY.onrender.com';

  /// Marker that [defaultApiBaseUrl] still has to be replaced.
  static const String placeholderMarker = 'REPLACE_AFTER_RENDER_DEPLOY';

  /// The configured URL: the override when given, else [defaultApiBaseUrl].
  /// Compile-time constant lookup, so the key is spelled out literally.
  static const String apiBaseUrl = String.fromEnvironment(
    'TRAVEL_ALERTS_API_BASE_URL',
    defaultValue: defaultApiBaseUrl,
  );

  /// True while [url] is still the unreplaced placeholder.
  static bool isPlaceholder(String url) => url.contains(placeholderMarker);
}
