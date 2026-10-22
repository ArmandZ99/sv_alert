import '../fetch/polite_fetcher.dart';
import '../model/model.dart';

/// What one adapter produced on one load.
class AdapterLoad {
  const AdapterLoad({
    required this.connection,
    required this.message,
    this.patterns = const [],
    this.fetchedAt,
    this.sourceTimestamp,
    this.validFrom,
    this.validTo,
  });

  /// A source that is not used, and why. Makes no request.
  const AdapterLoad.unavailable(String message, {SourceConnection? connection})
      : this(
          connection: connection ?? SourceConnection.unavailable,
          message: message,
        );

  final SourceConnection connection;
  final String message;
  final List<SchedulePattern> patterns;
  final DateTime? fetchedAt;
  final DateTime? sourceTimestamp;
  final DateTime? validFrom;
  final DateTime? validTo;
}

/// One provider. Everything specific to a provider (URLs, HTML or XML shapes,
/// quirks) stays inside its adapter; the rest of the system only sees
/// [SchedulePattern]s and a status.
///
/// An adapter must never invent data: if the source's structure is not what
/// the parser expects it throws [FormatException], and the pipeline reports
/// the source as unavailable.
abstract class SourceAdapter {
  SourceDescriptor get descriptor;

  /// Types of transport this source covers, for the status report.
  List<TransportKind> get kinds => [descriptor.kind];

  Future<AdapterLoad> load(PoliteFetcher fetcher, DateTime now);
}

/// A source deliberately not used, kept in the report so its state is visible.
class UnusedSourceAdapter extends SourceAdapter {
  UnusedSourceAdapter({
    required this.descriptor,
    required this.reason,
    this.connection = SourceConnection.unavailable,
  });

  @override
  final SourceDescriptor descriptor;
  final String reason;
  final SourceConnection connection;

  @override
  Future<AdapterLoad> load(PoliteFetcher fetcher, DateTime now) async =>
      AdapterLoad.unavailable(reason, connection: connection);
}

/// Romanian month names to numbers (lower case, diacritics folded).
const Map<String, int> romanianMonths = {
  'ianuarie': 1,
  'februarie': 2,
  'martie': 3,
  'aprilie': 4,
  'mai': 5,
  'iunie': 6,
  'iulie': 7,
  'august': 8,
  'septembrie': 9,
  'octombrie': 10,
  'noiembrie': 11,
  'decembrie': 12,
};

/// Lower-cases and folds Romanian diacritics (both cedilla and comma forms).
String fold(String input) {
  const map = {
    'ă': 'a',
    'â': 'a',
    'î': 'i',
    'ș': 's',
    'ş': 's',
    'ț': 't',
    'ţ': 't',
    'Ă': 'a',
    'Â': 'a',
    'Î': 'i',
    'Ș': 's',
    'Ş': 's',
    'Ț': 't',
    'Ţ': 't',
  };
  final b = StringBuffer();
  for (final rune in input.runes) {
    final c = String.fromCharCode(rune);
    b.write(map[c] ?? c.toLowerCase());
  }
  return b.toString();
}

/// Collapses whitespace, including non-breaking spaces.
String tidy(String input) =>
    input.replaceAll(' ', ' ').replaceAll(RegExp(r'\s+'), ' ').trim();

/// "HH:MM" to minutes after midnight, or null.
int? parseClock(String input) {
  final m = RegExp(r'^(\d{1,2}):(\d{2})$').firstMatch(tidy(input));
  if (m == null) return null;
  final h = int.parse(m.group(1)!);
  final min = int.parse(m.group(2)!);
  if (h > 23 || min > 59) return null;
  return h * 60 + min;
}

/// A calendar entry covering every day (for sources that publish no validity).
CalendarEntry everyDay() =>
    CalendarEntry(from: DateTime.utc(2000), to: DateTime.utc(2100));
