/// Non-secret configuration for reaching real transport data.
///
/// The app never talks to a data provider directly and never holds a provider
/// key: keys stay on a backend. The only setting the app may receive is the
/// base URL of that backend, passed at build time:
///
///     flutter run --dart-define=TRAVEL_ALERTS_API_BASE_URL=https://api.example.ro
///
/// If it is absent the app runs on explicit mock data.
class ProviderConfig {
  const ProviderConfig({this.apiBaseUrl});

  static const String environmentKey = 'TRAVEL_ALERTS_API_BASE_URL';

  /// Backend that serves normalized arrivals, or null for mock data only.
  final Uri? apiBaseUrl;

  bool get hasBackend => apiBaseUrl != null;

  /// Reads the build-time setting. Compile-time constant lookup, so it must be
  /// spelled out here rather than done through a variable key.
  static ConfigValidation fromEnvironment() =>
      validate(const String.fromEnvironment('TRAVEL_ALERTS_API_BASE_URL'));

  /// Validates a candidate base URL. Error messages never repeat the value, so
  /// a mistakenly pasted secret is not echoed into logs or the UI.
  static ConfigValidation validate(String? rawBaseUrl) {
    final raw = rawBaseUrl?.trim() ?? '';
    if (raw.isEmpty) {
      return const ConfigValidation(config: ProviderConfig(), errors: []);
    }

    final errors = <String>[];
    final uri = Uri.tryParse(raw);
    if (uri == null || !uri.hasScheme || uri.host.isEmpty) {
      return const ConfigValidation(
        config: ProviderConfig(),
        errors: ['The backend URL is not a valid absolute URL.'],
      );
    }

    final isLocal = const {
      'localhost',
      '127.0.0.1',
      '10.0.2.2', // Android emulator's alias for the host machine
    }.contains(uri.host);
    if (uri.scheme != 'https' && !(uri.scheme == 'http' && isLocal)) {
      errors.add('The backend URL must use https (http only for local dev).');
    }
    if (uri.userInfo.isNotEmpty) {
      errors.add('The backend URL must not contain credentials.');
    }
    if (uri.hasQuery) {
      errors.add('The backend URL must not contain a query string or keys.');
    }
    if (uri.hasFragment) {
      errors.add('The backend URL must not contain a fragment.');
    }

    return ConfigValidation(
      config: errors.isEmpty
          ? ProviderConfig(apiBaseUrl: uri)
          : const ProviderConfig(),
      errors: errors,
    );
  }
}

class ConfigValidation {
  const ConfigValidation({required this.config, required this.errors});

  /// A usable config: the backend URL when valid, otherwise mock-only.
  final ProviderConfig config;
  final List<String> errors;

  bool get isValid => errors.isEmpty;
}
