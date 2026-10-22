import 'dart:convert';
import 'dart:io';

import 'package:xml/xml.dart';
import 'package:xml/xml_events.dart';

import '../fetch/polite_fetcher.dart';
import '../model/model.dart';
import '../time/bucharest_time.dart';
import 'source_adapter.dart';

/// One published timetable file (a dataset resource on data.gov.ro).
class RailDataset {
  RailDataset({
    required this.url,
    required this.operatorName,
    required this.pageUrl,
    this.bundledPath,
  });

  /// Direct download URL of the XML file.
  final Uri url;
  final String operatorName;

  /// Human page of the dataset, shown as the service's source link.
  final String pageUrl;

  /// A copy of the file shipped with the service (`.xml` or `.xml.gz`). When
  /// it exists it is used instead of downloading [url]: data.gov.ro can be
  /// slow or unreachable from a hosted server, and the open licence allows
  /// redistribution. Null means always download.
  final String? bundledPath;
}

class ParsedRailTimetable {
  const ParsedRailTimetable({
    required this.patterns,
    required this.validFrom,
    required this.validTo,
    required this.exportDate,
    required this.trainsSeen,
    required this.skippedCalendars,
  });

  final List<SchedulePattern> patterns;
  final DateTime validFrom;
  final DateTime validTo;
  final DateTime exportDate;
  final int trainsSeen;

  /// Calendar entries not understood and therefore not used.
  final int skippedCalendars;
}

/// Scheduled train arrivals at Suceava, Suceava Nord and Suceava Vest from the
/// official annual passenger timetable published as open data on data.gov.ro
/// (licence OGL-ROU-1.0). It is a static planning timetable: it contains no
/// delays and no real-time information.
///
/// How the file is read (structure inferred from the data, the file's schema
/// document is not published with it):
/// * `Tren` is a train; `ElementTrasa` is one leg between two stations with
///   `OraP` (departure) and `OraS` (arrival) in seconds after midnight of the
///   operating day (values past 86400 are the following day).
/// * The dwell at a station is described on the leg that *leaves* it
///   (`TipOprire`). A stop counts as a passenger stop when that type is `C`
///   (commercial) or `A`, or when the train ends there. `N` means the train
///   passes without stopping; `T` (technical) is not counted. Cross-check: for
///   Suceava Vest this rule gives exactly the 4 trains a public station page
///   lists.
/// * `CalendarTren.Zile` is a bit mask; bits 0-6 are Monday-Sunday of the
///   operating day. Higher bits are undocumented (probably holidays) and are
///   ignored, which is a known limitation.
class RailTimetableAdapter extends SourceAdapter {
  RailTimetableAdapter({required this.datasets});

  final List<RailDataset> datasets;

  static const String sourceId = 'ro-rail-open-timetable';

  static const Map<String, String> stationNames = {
    '51607': 'Gara Suceava',
    '51645': 'Gara Suceava Nord',
    '54439': 'Gara Suceava Vest',
  };

  @override
  SourceDescriptor get descriptor => SourceDescriptor(
        id: sourceId,
        name: 'Orar tren - date deschise (data.gov.ro)',
        kind: TransportKind.train,
        url: 'https://data.gov.ro/dataset/mers-tren-sntfc-cfr-calatori-s-a',
      );

  @override
  Future<AdapterLoad> load(PoliteFetcher fetcher, DateTime now) async {
    final patterns = <SchedulePattern>[];
    DateTime? from;
    DateTime? to;
    DateTime? exported;
    DateTime? fetchedAt;
    final failures = <String>[];
    var skipped = 0;
    var usedBundled = false;

    for (final dataset in datasets) {
      try {
        final bundled = dataset.bundledPath == null
            ? null
            : await readBundled(dataset.bundledPath!);
        final String text;
        final DateTime loadedAt;
        if (bundled != null) {
          text = bundled;
          loadedAt = now;
          usedBundled = true;
        } else {
          final result = await fetcher.get(
            dataset.url,
            maxAge: const Duration(hours: 24),
          );
          text = result.text;
          loadedAt = result.fetchedAt;
        }
        final parsed = await parse(
          text,
          operatorName: dataset.operatorName,
          sourceUrl: dataset.pageUrl,
        );
        patterns.addAll(parsed.patterns);
        skipped += parsed.skippedCalendars;
        from = _min(from, parsed.validFrom);
        to = _max(to, parsed.validTo);
        exported = _max(exported, parsed.exportDate);
        fetchedAt = _min(fetchedAt, loadedAt);
      } on FetchException catch (e) {
        failures.add('${dataset.operatorName}: ${e.message}');
      } on FormatException catch (e) {
        failures.add('${dataset.operatorName}: ${e.message}');
      }
    }

    if (patterns.isEmpty) {
      throw FetchException(
        failures.isEmpty
            ? 'Nu s-a găsit niciun tren la Suceava în fișierele de orar.'
            : failures.join(' '),
      );
    }

    final today = BucharestTime.serviceDateOf(now);
    final expired = to != null && to.isBefore(today);
    final notes = <String>[
      'Orar anual programat (date deschise OGL-ROU-1.0), fără întârzieri.',
      if (usedBundled)
        'Fișierele de orar sunt incluse în serviciu (export din '
            '${_date(exported)}), nu descărcate la fiecare pornire; se '
            'înlocuiesc la publicarea orarului nou.',
      if (failures.isNotEmpty) 'Fișiere indisponibile: ${failures.join(' ')}',
      if (skipped > 0)
        '$skipped intrări de calendar nerecunoscute au fost omise.',
      'Doar zilele săptămânii sunt interpretate; regulile pentru sărbători nu.',
    ];
    return AdapterLoad(
      connection: expired
          ? SourceConnection.unavailable
          : SourceConnection.scheduledOnly,
      message: expired
          ? 'Orarul a expirat; actualizați adresa fișierelor din data.gov.ro.'
          : notes.join(' '),
      patterns: expired ? const [] : patterns,
      fetchedAt: fetchedAt,
      sourceTimestamp: exported,
      validFrom: from,
      validTo: to,
    );
  }

  /// The text of a bundled file, or null when there is none. Reads plain XML
  /// or gzip (chosen by the `.gz` ending). A file that exists but cannot be
  /// decoded is a [FormatException], not a silent fall-back to the network.
  static Future<String?> readBundled(String path) async {
    final file = File(path);
    if (!await file.exists()) return null;
    try {
      final bytes = await file.readAsBytes();
      final raw = path.endsWith('.gz') ? gzip.decode(bytes) : bytes;
      return utf8.decode(raw, allowMalformed: true);
    } on FileSystemException {
      return null;
    } on FormatException {
      throw FormatException('Fișierul de orar inclus nu poate fi citit: $path');
    }
  }

  static String _date(DateTime? d) => d == null
      ? '?'
      : '${d.day.toString().padLeft(2, '0')}.'
          '${d.month.toString().padLeft(2, '0')}.${d.year}';

  /// Streams through the XML one train at a time so the 12 MB file never
  /// becomes a full document in memory. Throws [FormatException] when the
  /// header is missing.
  static Future<ParsedRailTimetable> parse(
    String xml, {
    required String operatorName,
    required String sourceUrl,
  }) async {
    final header = RegExp(r'<Mt\b[^>]*>').firstMatch(xml)?.group(0);
    DateTime? attr(String name) {
      final m = RegExp('$name="(\\d{8})"').firstMatch(header ?? '');
      return m == null ? null : _yyyymmdd(m.group(1)!);
    }

    final validFrom = attr('MtValabilDeLa');
    final validTo = attr('MtValabilPinaLa');
    final exportDate = attr('DataExport');
    if (validFrom == null || validTo == null || exportDate == null) {
      throw const FormatException('Antetul orarului (Mt) lipsește.');
    }

    final patterns = <SchedulePattern>[];
    var trains = 0;
    var skippedCalendars = 0;

    final stream = Stream.value(xml)
        .toXmlEvents()
        .selectSubtreeEvents((e) => e.name == 'Tren')
        .toXmlNodes()
        .flatten();
    await for (final node in stream) {
      if (node is! XmlElement || node.name.local != 'Tren') continue;
      trains++;
      final built = _trainPatterns(node, operatorName, sourceUrl);
      patterns.addAll(built.$1);
      skippedCalendars += built.$2;
    }
    if (trains == 0) {
      throw const FormatException('Nu s-au găsit trenuri în fișier.');
    }

    return ParsedRailTimetable(
      patterns: patterns,
      validFrom: validFrom,
      validTo: validTo,
      exportDate: exportDate,
      trainsSeen: trains,
      skippedCalendars: skippedCalendars,
    );
  }

  static (List<SchedulePattern>, int) _trainPatterns(
    XmlElement train,
    String operatorName,
    String sourceUrl,
  ) {
    final legs = [
      for (final e in train.findAllElements('ElementTrasa'))
        (
          fromCode: e.getAttribute('CodStaOrigine') ?? '',
          toCode: e.getAttribute('CodStaDest') ?? '',
          from: e.getAttribute('DenStaOrigine') ?? '',
          to: e.getAttribute('DenStaDestinatie') ?? '',
          arrive: int.tryParse(e.getAttribute('OraS') ?? ''),
          stop: e.getAttribute('TipOprire') ?? '',
        ),
    ];
    // Drop the closing "X -> X" marker some trains end with.
    final real = [
      for (final l in legs)
        if (l.fromCode != l.toCode) l
    ];
    if (real.isEmpty) return (const [], 0);
    if (!real.any((l) => stationNames.containsKey(l.toCode))) {
      return (const [], 0);
    }

    // For leg i, the stop at its destination is described by leg i+1.
    String stopAfter(int i) {
      if (i + 1 >= real.length) return 'END';
      final next = real[i + 1];
      return next.fromCode == real[i].toCode ? next.stop : 'N';
    }

    bool isPassengerStop(String type) =>
        type == 'C' || type == 'A' || type == 'END';

    final route = <String>[_cleanName(real.first.from)];
    for (var i = 0; i < real.length; i++) {
      final type = stopAfter(i);
      if (i == real.length - 1 || type == 'C' || type == 'A') {
        route.add(_cleanName(real[i].to));
      }
    }
    final stops = _dedupe(route);

    final calendars = <CalendarEntry>[];
    var skipped = 0;
    for (final c in train.findAllElements('CalendarTren')) {
      final from = _yyyymmdd(c.getAttribute('DeLa') ?? '');
      final to = _yyyymmdd(c.getAttribute('PinaLa') ?? '');
      final mask = int.tryParse(c.getAttribute('Zile') ?? '');
      if (c.getAttribute('Tip') != 'Da' ||
          from == null ||
          to == null ||
          mask == null) {
        skipped++;
        continue;
      }
      final days = <int>{
        for (var bit = 0; bit < 7; bit++)
          if (mask & (1 << bit) != 0) bit + 1, // bit 0 = Monday = 1
      };
      if (days.isEmpty) {
        skipped++;
        continue;
      }
      calendars.add(CalendarEntry(from: from, to: to, weekdays: days));
    }
    if (calendars.isEmpty) return (const [], skipped);

    final category = train.getAttribute('CategorieTren') ?? '';
    final number = train.getAttribute('Numar') ?? '';
    final patterns = <SchedulePattern>[];
    for (var i = 0; i < real.length; i++) {
      final name = stationNames[real[i].toCode];
      final seconds = real[i].arrive;
      if (name == null || seconds == null) continue;
      if (!isPassengerStop(stopAfter(i))) continue;
      patterns.add(
        SchedulePattern(
          serviceNumber: '$category $number'.trim(),
          operatorName: operatorName,
          routeStops: stops.length >= 2 ? stops : [...stops, name],
          arrivalPoint: name,
          arrivalMinutes: seconds ~/ 60,
          calendar: calendars,
          sourceUrl: sourceUrl,
        ),
      );
    }
    return (patterns, skipped);
  }

  /// Folds the timetable's internal station names into readable ones:
  /// cedilla letters to comma-below, and operational suffixes dropped.
  static String _cleanName(String raw) {
    var s = raw
        .replaceAll('ş', 'ș')
        .replaceAll('Ş', 'Ș')
        .replaceAll('ţ', 'ț')
        .replaceAll('Ţ', 'Ț');
    s = s.replaceAll(RegExp(r'\(\d+\)'), '');
    s = s.replaceAll(RegExp(r'\s+(Gr\.\s?[A-Z]|Hm\.|hc\.|h\.|Ram\..*)$'), '');
    return tidy(s);
  }

  static List<String> _dedupe(List<String> names) {
    final out = <String>[];
    for (final n in names) {
      if (out.isEmpty || out.last != n) out.add(n);
    }
    return out;
  }

  static DateTime? _yyyymmdd(String s) {
    if (!RegExp(r'^\d{8}$').hasMatch(s)) return null;
    return DateTime.utc(
      int.parse(s.substring(0, 4)),
      int.parse(s.substring(4, 6)),
      int.parse(s.substring(6, 8)),
    );
  }

  static DateTime? _min(DateTime? a, DateTime b) =>
      a == null || b.isBefore(a) ? b : a;
  static DateTime? _max(DateTime? a, DateTime b) =>
      a == null || b.isAfter(a) ? b : a;
}
