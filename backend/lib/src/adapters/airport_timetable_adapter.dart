import 'package:html/parser.dart' as html;

import '../fetch/polite_fetcher.dart';
import '../model/model.dart';
import '../time/bucharest_time.dart';
import 'airport_pdf_timetable.dart';
import 'pdf_text_extractor.dart';
import 'source_adapter.dart';

/// Scheduled flight arrivals from the airport's published timetables. Scheduled
/// data only: nothing here has estimated or actual times.
///
/// **Where the data is** (checked on the raw HTTP response, 2026-10-21): the
/// page has HTML tables for **one season only** (today the summer period 29
/// March - 24 October 2026). The next season (25 October 2026 - 27 March 2027)
/// appears in the HTML only as the text of links to PDFs, not as tables. So:
///
/// * The tables, with the period stated in their heading, are parsed from the
///   HTML (see [parse]).
/// * Every other arrivals PDF the page links to whose period has not ended and
///   starts soon is fetched and read with a [PdfTextExtractor] (see
///   [AirportPdfTimetableParser]).
/// * Each season keeps its own period, so seasons never mix: a service date
///   belongs to exactly one. A PDF whose period equals or overlaps the HTML
///   season is skipped, so a page that later switches to HTML tables for the
///   new season produces no duplicates.
/// * One failing season does not take down another: a valid summer timetable is
///   still served when the winter PDF cannot be read, and vice versa. The
///   source is reported unavailable only when no season covers today or later.
class AirportTimetableAdapter extends SourceAdapter {
  AirportTimetableAdapter({
    Uri? pageUrl,
    PdfTextExtractor? pdfExtractor,
    this.prefetchDays = 60,
  })  : pageUrl = pageUrl ??
            Uri.parse('https://aeroportsuceava.ro/ro/2016-01-29-10-35-08'),
        pdfExtractor = pdfExtractor ?? PdftotextExtractor();

  final Uri pageUrl;
  final PdfTextExtractor pdfExtractor;

  /// A later season's PDF is fetched once it starts within this many days.
  final int prefetchDays;

  static const String sourceId = 'scv-airport-timetable';

  @override
  SourceDescriptor get descriptor => SourceDescriptor(
        id: sourceId,
        name: 'Aeroportul Suceava - orar publicat',
        kind: TransportKind.flight,
        url: pageUrl.toString(),
      );

  static const arrivalAirport = AirportPdfTimetableParser.arrivalAirport;

  static const _days = {
    'LUNI': DateTime.monday,
    'MARTI': DateTime.tuesday,
    'MIERCURI': DateTime.wednesday,
    'JOI': DateTime.thursday,
    'VINERI': DateTime.friday,
    'SAMBATA': DateTime.saturday,
    'DUMINICA': DateTime.sunday,
  };

  @override
  Future<AdapterLoad> load(PoliteFetcher fetcher, DateTime now) async {
    final page = await fetcher.get(pageUrl);
    final body = page.text;
    final today = BucharestTime.serviceDateOf(now);

    final seasons = <_Season>[];
    final notes = <String>[];

    // 1. The season published as HTML tables.
    final inline = parse(body);
    seasons.add(
      _Season(parsed: inline, origin: 'pagina', fetchedAt: page.fetchedAt),
    );

    // 2. Other seasons, published as PDFs linked from the page.
    final documents = discoverArrivalDocuments(body, pageUrl);
    for (final doc in documents) {
      if (doc.validTo.isBefore(today)) continue; // already over
      if (doc.validFrom.difference(today).inDays > prefetchDays) continue;
      // The HTML season is preferred; overlapping seasons would duplicate.
      if (seasons.any(
        (s) => _overlaps(
          doc.validFrom,
          doc.validTo,
          s.parsed.validFrom,
          s.parsed.validTo,
        ),
      )) {
        continue;
      }

      final label = '${_d(doc.validFrom)}-${_d(doc.validTo)}';
      try {
        final file = await fetcher.get(
          doc.url,
          maxAge: const Duration(hours: 24),
        );
        final text = await pdfExtractor.extract(file.bytes);
        final parsed = AirportPdfTimetableParser.parse(text);
        if (parsed.validFrom != doc.validFrom ||
            parsed.validTo != doc.validTo) {
          notes.add(
            'Orarul PDF $label a fost ignorat: perioada din document '
            '(${_d(parsed.validFrom)}-${_d(parsed.validTo)}) nu corespunde '
            'legăturii.',
          );
          continue;
        }
        seasons.add(
          _Season(parsed: parsed, origin: 'PDF', fetchedAt: file.fetchedAt),
        );
        if (parsed.rejected.isNotEmpty) {
          notes.add(
            '${parsed.rejected.length} rânduri din PDF-ul $label au fost '
            'respinse: ${parsed.rejected.join('; ')}.',
          );
        }
      } on FetchException catch (e) {
        notes.add('Orarul PDF $label nu a putut fi preluat: ${e.message}');
      } on PdfExtractionException catch (e) {
        notes.add('Orarul PDF $label nu a putut fi citit: ${e.message}');
      } on FormatException catch (e) {
        notes.add(
          'Orarul PDF $label a fost ignorat, structura nu este cea '
          'așteptată (${e.message}).',
        );
      }
    }

    // A season that is over contributes nothing.
    final usable = [
      for (final s in seasons)
        if (!s.parsed.validTo.isBefore(today)) s,
    ];
    if (usable.isEmpty) {
      // The last end among everything the page names, including PDF seasons
      // that were not read because they are already over.
      final lastEnd = [
        ...seasons.map((s) => s.parsed.validTo),
        ...documents.map((d) => d.validTo),
      ].reduce((a, b) => a.isAfter(b) ? a : b);
      return AdapterLoad(
        connection: SourceConnection.unavailable,
        message: 'Niciun orar publicat nu acoperă data curentă: ultimul a '
                'expirat la ${_d(lastEnd)}. ${notes.join(' ')}'
            .trim(),
        fetchedAt: page.fetchedAt,
        validFrom: inline.validFrom,
        validTo: inline.validTo,
      );
    }

    final periods = [
      for (final s in usable)
        '${_d(s.parsed.validFrom)}-${_d(s.parsed.validTo)} (${s.origin})',
    ];
    DateTime earliest(Iterable<DateTime> v) =>
        v.reduce((a, b) => a.isBefore(b) ? a : b);
    DateTime latest(Iterable<DateTime> v) =>
        v.reduce((a, b) => a.isAfter(b) ? a : b);

    return AdapterLoad(
      connection: SourceConnection.scheduledOnly,
      message: 'Orar programat, perioade: ${periods.join(', ')}. Fără '
              'estimări sau întârzieri. ${notes.join(' ')}'
          .trim(),
      patterns: [for (final s in usable) ...s.parsed.patterns],
      fetchedAt: earliest(usable.map((s) => s.fetchedAt)),
      validFrom: earliest(usable.map((s) => s.parsed.validFrom)),
      validTo: latest(usable.map((s) => s.parsed.validTo)),
    );
  }

  /// The season published as HTML tables. Throws [FormatException] if the page
  /// no longer has the expected shape.
  static ParsedAirportTimetable parse(String body) {
    final range = _tableValidity(body);
    if (range == null) {
      throw const FormatException('Perioada de valabilitate nu a fost găsită.');
    }
    final doc = html.parse(body);

    final grouped = <String, _Row>{};
    var tablesFound = 0;
    for (final entry in _days.entries) {
      final pane = doc.getElementById('${entry.key}-sosiri');
      if (pane == null) continue;
      tablesFound++;
      for (final tr in pane.querySelectorAll('tr.table__row')) {
        final cells = <String, String>{
          for (final td in tr.querySelectorAll('td'))
            if (td.attributes['data-heading'] != null)
              td.attributes['data-heading']!: tidy(td.text),
        };
        final number = cells['INDICATIV'];
        final origin = cells['DE LA'];
        final destination = cells['DESTINATIA'] ?? '';
        final arrival = _arrival(cells['SOSIRE'] ?? '');
        if (number == null ||
            number.isEmpty ||
            origin == null ||
            origin.isEmpty) {
          continue;
        }
        if (!destination.toUpperCase().contains('SCV')) {
          continue; // not an arrival
        }
        if (arrival == null) continue;

        final key = '$number|$origin|$arrival|${cells['COMPANIA']}';
        grouped
            .putIfAbsent(
              key,
              () => _Row(
                number: number,
                airline: _title(cells['COMPANIA'] ?? ''),
                origin: origin,
                arrivalMinutes: arrival,
              ),
            )
            .weekdays
            .add(entry.value);
      }
    }
    if (tablesFound == 0) {
      throw const FormatException('Tabelele de sosiri nu au fost găsite.');
    }

    return ParsedAirportTimetable(
      validFrom: range.$1,
      validTo: range.$2,
      patterns: [
        for (final row in grouped.values)
          SchedulePattern(
            serviceNumber: row.number,
            operatorName: row.airline.isEmpty ? null : row.airline,
            routeStops: [row.origin, arrivalAirport],
            arrivalPoint: arrivalAirport,
            arrivalMinutes: row.arrivalMinutes,
            calendar: [
              CalendarEntry(
                from: range.$1,
                to: range.$2,
                weekdays: row.weekdays,
              ),
            ],
          ),
      ],
    );
  }

  /// Links to arrivals PDFs, each with the period named in its link text.
  /// Only same-host `https` PDF links are accepted, never an arbitrary URL.
  static List<ArrivalDocument> discoverArrivalDocuments(
    String body,
    Uri pageUrl,
  ) {
    final result = <ArrivalDocument>[];
    final seen = <Uri>{};
    for (final a in html.parse(body).querySelectorAll('a[href]')) {
      final href = a.attributes['href']!;
      if (!href.toLowerCase().endsWith('.pdf')) continue;
      final text = tidy(a.text);
      final isArrivals =
          fold(text).contains('sosiri') || fold(href).contains('sosiri');
      if (!isArrivals) continue;
      final period = AirportPdfTimetableParser.periodIn(text);
      if (period == null) continue;
      final url = pageUrl.resolve(href);
      if (url.scheme != 'https' || url.host != pageUrl.host) continue;
      if (!seen.add(url)) continue;
      result.add(
        ArrivalDocument(url: url, validFrom: period.$1, validTo: period.$2),
      );
    }
    result.sort((a, b) => a.validFrom.compareTo(b.validFrom));
    return result;
  }

  /// The period stated by the heading above the arrivals tables: the last
  /// heading before the tables that is not inside a link. (The PDF links also
  /// carry period texts; they name other seasons and must not be mistaken for
  /// the tables' own.)
  static (DateTime, DateTime)? _tableValidity(String body) {
    final start = body.indexOf('id="LUNI-sosiri"');
    if (start < 0) return null;
    var before = body.substring(0, start);
    before = before.replaceAll(RegExp(r'<a\b[^>]*>.*?</a>', dotAll: true), ' ');
    before = before.replaceAll(RegExp(r'<[^>]+>'), ' ');
    (DateTime, DateTime)? last;
    for (final m in RegExp(r'PERIOADA[^\n]{0,80}').allMatches(before)) {
      final period = AirportPdfTimetableParser.periodIn(m.group(0)!);
      if (period != null) last = period;
    }
    return last;
  }

  /// "08:45" or "01:35 (+1)" to minutes after the operating day's midnight.
  static int? _arrival(String text) {
    final m = RegExp(
      r'^(\d{1,2}:\d{2})(?:\s*\(\+(\d)\))?$',
    ).firstMatch(tidy(text));
    if (m == null) return null;
    final minutes = parseClock(m.group(1)!);
    if (minutes == null) return null;
    return minutes + 1440 * (int.tryParse(m.group(2) ?? '') ?? 0);
  }

  static bool _overlaps(
    DateTime aFrom,
    DateTime aTo,
    DateTime bFrom,
    DateTime bTo,
  ) =>
      !aFrom.isAfter(bTo) && !bFrom.isAfter(aTo);

  static String _title(String s) => tidy(s)
      .toLowerCase()
      .split(' ')
      .map((w) => w.isEmpty ? w : w[0].toUpperCase() + w.substring(1))
      .join(' ');

  static String _d(DateTime d) => '${d.day.toString().padLeft(2, '0')}.'
      '${d.month.toString().padLeft(2, '0')}.${d.year}';
}

class _Season {
  _Season({
    required this.parsed,
    required this.origin,
    required this.fetchedAt,
  });

  final ParsedAirportTimetable parsed;

  /// "pagina" (HTML tables) or "PDF".
  final String origin;
  final DateTime fetchedAt;
}

class _Row {
  _Row({
    required this.number,
    required this.airline,
    required this.origin,
    required this.arrivalMinutes,
  });

  final String number;
  final String airline;
  final String origin;
  final int arrivalMinutes;
  final Set<int> weekdays = {};
}
