import 'adapters/airport_timetable_adapter.dart';
import 'adapters/airport_transfer_adapter.dart';
import 'adapters/pdf_text_extractor.dart';
import 'adapters/rail_timetable_adapter.dart';
import 'adapters/source_adapter.dart';
import 'adapters/tasa_adapter.dart';
import 'adapters/unused_sources.dart';
import 'server/handler.dart';

/// Official passenger timetable files on data.gov.ro (OGL-ROU-1.0), valid from
/// the second Sunday of December to the second Saturday of December the
/// following year. The URLs change with each yearly publication: update them
/// every December (or override with the environment variables below).
final defaultRailDatasets = [
  RailDataset(
    url: Uri.https(
      'data.gov.ro',
      '/dataset/c4f71dbb-de39-49b2-b697-5b60a5f299a2/resource/'
          '0f67143e-bb88-4a06-8e7a-b35b1eb91329/download/'
          'trenuri-2025-2026_sntfc.xml',
    ),
    operatorName: 'CFR Călători',
    pageUrl: 'https://data.gov.ro/dataset/mers-tren-sntfc-cfr-calatori-s-a',
  ),
  RailDataset(
    url: Uri.https(
      'data.gov.ro',
      '/dataset/b4e2ce0b-6935-44b1-8e9d-f3999123358a/resource/'
          '1a083cf5-d37c-4618-aeb8-3f1ba0dd22dc/download/'
          'trenuri-2025-2026_interregional-calatori.xml',
    ),
    operatorName: 'Interregional Călători',
    pageUrl: 'https://data.gov.ro/dataset/mers-tren-interregional-calatori',
  ),
];

/// Settings read from the environment. Nothing here is secret except
/// [aeroDataBoxKey], which stays on the server and is never sent to the app.
class BackendConfig {
  BackendConfig({
    required this.contact,
    this.port = 8080,
    this.host = '127.0.0.1',
    this.aeroDataBoxKey,
    this.pdftotextPath = 'pdftotext',
    this.pdfExtractor,
    this.corsAllowOrigin,
    List<RailDataset>? railDatasets,
  }) : railDatasets = railDatasets ?? defaultRailDatasets;

  /// Contact (email or URL) put in the User-Agent so site owners can reach the
  /// operator of this service. Required.
  final String contact;
  final int port;

  /// Interface to listen on. Loopback by default; set HOST=0.0.0.0 to serve
  /// other machines (behind a reverse proxy that adds TLS).
  final String host;
  final String? aeroDataBoxKey;

  /// The `pdftotext` command used to read the airport's seasonal PDFs.
  final String pdftotextPath;

  /// Replaces the `pdftotext` command (tests, or another extractor).
  final PdfTextExtractor? pdfExtractor;

  /// Browser origin allowed to call the API (testing with Swagger UI). Null
  /// means no CORS headers at all, which is the default.
  final String? corsAllowOrigin;
  final List<RailDataset> railDatasets;

  String get userAgent => 'SuceavaTravelAlerts/0.1 (+$contact)';

  /// Returns the config, or throws [ArgumentError] naming the missing setting.
  factory BackendConfig.fromEnvironment(Map<String, String> env) {
    final contact = env['TRAVEL_ALERTS_CONTACT']?.trim() ?? '';
    if (contact.isEmpty) {
      throw ArgumentError(
        'Set TRAVEL_ALERTS_CONTACT to an email or URL: it is sent in the '
        'User-Agent so source sites can reach you.',
      );
    }
    final port = int.tryParse(env['PORT'] ?? '') ?? 8080;
    final key = env['AERODATABOX_API_KEY']?.trim();
    final host = env['HOST']?.trim();
    final pdftotext = env['PDFTOTEXT_PATH']?.trim();
    final cors = env['CORS_ALLOW_ORIGIN']?.trim();
    if (cors != null && cors.isNotEmpty && !isValidCorsOrigin(cors)) {
      throw ArgumentError(
        'CORS_ALLOW_ORIGIN must be * or an origin such as http://127.0.0.1:8081 '
        '(scheme, host and optional port, no path).',
      );
    }

    // Dataset URLs change every December: allow overriding them.
    List<RailDataset> datasets() {
      final sntfc = env['RAIL_SNTFC_URL']?.trim();
      final inter = env['RAIL_INTERREGIONAL_URL']?.trim();
      return [
        for (final d in defaultRailDatasets)
          RailDataset(
            url: Uri.parse(
              d.operatorName == 'CFR Călători' &&
                      sntfc != null &&
                      sntfc.isNotEmpty
                  ? sntfc
                  : d.operatorName == 'Interregional Călători' &&
                          inter != null &&
                          inter.isNotEmpty
                      ? inter
                      : d.url.toString(),
            ),
            operatorName: d.operatorName,
            pageUrl: d.pageUrl,
          ),
      ];
    }

    return BackendConfig(
      contact: contact,
      port: port,
      host: (host == null || host.isEmpty) ? '127.0.0.1' : host,
      aeroDataBoxKey: (key == null || key.isEmpty) ? null : key,
      pdftotextPath:
          (pdftotext == null || pdftotext.isEmpty) ? 'pdftotext' : pdftotext,
      corsAllowOrigin: (cors == null || cors.isEmpty) ? null : cors,
      railDatasets: datasets(),
    );
  }

  List<SourceAdapter> buildAdapters() => [
        AirportTimetableAdapter(
          pdfExtractor:
              pdfExtractor ?? PdftotextExtractor(executable: pdftotextPath),
        ),
        AirportTransferAdapter(),
        TasaAdapter(),
        RailTimetableAdapter(datasets: railDatasets),
        UnusedSources.aeroDataBox(hasKey: aeroDataBoxKey != null),
        UnusedSources.tarsin(),
        UnusedSources.autogari(),
      ];
}
