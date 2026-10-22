import '../model/model.dart';
import 'source_adapter.dart';

/// One seasonal arrivals timetable (a period and its recurring flights).
class ParsedAirportTimetable {
  const ParsedAirportTimetable({
    required this.patterns,
    required this.validFrom,
    required this.validTo,
    this.rejected = const [],
  });

  final List<SchedulePattern> patterns;
  final DateTime validFrom;
  final DateTime validTo;

  /// Rows that were not used, each with the reason. Never silently dropped.
  final List<String> rejected;
}

/// A seasonal arrivals PDF the airport page links to.
class ArrivalDocument {
  const ArrivalDocument({
    required this.url,
    required this.validFrom,
    required this.validTo,
  });

  final Uri url;
  final DateTime validFrom;
  final DateTime validTo;
}

/// Reads the airport's seasonal arrivals PDF from `pdftotext -raw` text.
///
/// What the PDF is (checked on the real winter file): a text PDF with a title
/// "... PENTRU PERIOADA 25 OCTOMBRIE 2026 - 27 MARTIE 2027", a column header,
/// and one table row per flight. In raw order each row is a single line:
///
///   `Luni W4 3612 WIZZ AIR A32Q Roma Fiumicino (FCO) Suceava (SCV) 05:30 08:50`
///
/// with the aircraft code sometimes missing, and an optional observation that
/// follows the row on its own lines: `Începând din` / `Operează până pe`, then
/// a date. Dates are inclusive: every date seen falls on the weekday of its row.
///
/// Rules:
/// * The title period is the validity. Dated observations only narrow it, and
///   no service is produced outside it.
/// * Same assumptions as the HTML tables: the day is the operating (departure)
///   day, the arrival time is Suceava time, `(+1)` is the next calendar day.
/// * Nothing unreadable is guessed. A row followed by an observation that is
///   not one of the two known forms is rejected.
/// * Plausibility check: for one origin the arrival time minus the departure
///   time is a fixed property of the route (clock-time difference, constant
///   within a season). A row that differs from its origin's median by more than
///   [durationToleranceMinutes] is rejected, which catches transposed times in
///   the source (the real winter PDF has one such pair on a Thursday). Only
///   applied to origins with at least [minRowsForCheck] rows.
abstract final class AirportPdfTimetableParser {
  static const int durationToleranceMinutes = 25;
  static const int minRowsForCheck = 3;

  static const _days = {
    'luni': DateTime.monday,
    'marti': DateTime.tuesday,
    'miercuri': DateTime.wednesday,
    'joi': DateTime.thursday,
    'vineri': DateTime.friday,
    'sambata': DateTime.saturday,
    'duminica': DateTime.sunday,
  };

  static final RegExp _period = RegExp(
    r'PERIOADA\s+(\d{1,2})\s+([A-Za-zĂÂÎȘŞȚŢăâîșşțţ]+)\s+(\d{4})\s*[–—-]\s*'
    r'(\d{1,2})\s+([A-Za-zĂÂÎȘŞȚŢăâîșşțţ]+)\s+(\d{4})',
    caseSensitive: false,
  );

  static final RegExp _row = RegExp(
    r'^(Luni|Mar[țţt]i|Miercuri|Joi|Vineri|S[âa]mb[ăa]t[ăa]|Duminic[ăa])\s+'
    r'(.+?)\s+Suceava \(SCV\)\s+(\d{1,2}:\d{2})\s+(\d{1,2}:\d{2})'
    r'(?:\s*\(\+(\d)\))?$',
  );

  static final RegExp _date = RegExp(r'(\d{2})\.(\d{2})\.(\d{4})');

  static bool _isFurniture(String folded) =>
      folded.startsWith('orarul zborurilor') ||
      folded == 'sosiri' ||
      folded.startsWith('ziua nr') ||
      folded == 'ora de' ||
      folded == 'plecare**' ||
      folded == 'sosire**' ||
      folded.startsWith('observati') ||
      folded.startsWith('* acest program') ||
      folded.startsWith('** ore locale') ||
      folded.startsWith('(+1) reprezinta');

  /// Throws [FormatException] if this is not an arrivals timetable of the
  /// expected shape.
  static ParsedAirportTimetable parse(String text) {
    final lines = [
      for (final raw in text.split(RegExp(r'\r?\n')))
        if (tidy(raw.replaceAll('\f', '')).isNotEmpty)
          tidy(raw.replaceAll('\f', '')),
    ];

    final period = _periodOf(lines.join('\n'));
    if (period == null) {
      throw const FormatException('Perioada orarului PDF nu a fost găsită.');
    }
    final folded = [for (final l in lines) fold(l)];
    if (!folded.any((l) => l.startsWith('ziua nr'))) {
      throw const FormatException('Antetul tabelului PDF lipsește.');
    }
    if (folded.any((l) => l == 'plecari')) {
      throw const FormatException('PDF-ul conține plecări, nu sosiri.');
    }
    if (!folded.contains('sosiri')) {
      throw const FormatException('PDF-ul nu este un orar de sosiri.');
    }

    final rows = <_PdfRow>[];
    final rejected = <String>[];
    String? pendingLabel;

    for (var i = 0; i < lines.length; i++) {
      final line = lines[i];
      final f = folded[i];
      final m = _row.firstMatch(line);

      if (m != null) {
        pendingLabel = null;
        final row = _parseRow(m);
        if (row == null) {
          rejected.add('«$line»: rând necitibil');
          rows.add(_PdfRow.invalid(line));
        } else {
          rows.add(row);
        }
        continue;
      }
      if (_isFurniture(f)) continue;
      if (rows.isEmpty) continue; // title or preamble lines

      // Observation lines belong to the row above them.
      final label = f.startsWith('incepand din')
          ? 'from'
          : f.startsWith('opereaza pana pe')
              ? 'until'
              : null;
      final dateMatch = _date.firstMatch(line);
      if (label != null && dateMatch != null) {
        _attach(rows.last, label, dateMatch);
        pendingLabel = null;
      } else if (label != null) {
        pendingLabel = label;
      } else if (pendingLabel != null &&
          dateMatch != null &&
          dateMatch.start == 0 &&
          dateMatch.end == line.length) {
        _attach(rows.last, pendingLabel, dateMatch);
        pendingLabel = null;
      } else {
        rows.last.unreadable = line;
        pendingLabel = null;
      }
    }

    if (rows.isEmpty) {
      throw const FormatException('Nu s-au găsit rânduri de zbor în PDF.');
    }

    _plausibility(rows);

    final grouped = <String, _Group>{};
    for (final row in rows) {
      if (row.invalid != null) continue;
      final problem = row.problem(period);
      if (problem != null) {
        rejected.add('${row.label}: $problem');
        continue;
      }
      final from = row.from != null && row.from!.isAfter(period.$1)
          ? row.from!
          : period.$1;
      final to = row.until != null && row.until!.isBefore(period.$2)
          ? row.until!
          : period.$2;
      final key = '${row.number}|${row.origin}|${row.arrivalMinutes}|$from|$to';
      grouped
          .putIfAbsent(
            key,
            () => _Group(row, from, to),
          )
          .weekdays
          .add(row.weekday!);
    }

    return ParsedAirportTimetable(
      validFrom: period.$1,
      validTo: period.$2,
      rejected: rejected,
      patterns: [
        for (final g in grouped.values)
          SchedulePattern(
            serviceNumber: g.row.number!,
            operatorName: g.row.airline!.isEmpty ? null : g.row.airline,
            routeStops: [g.row.origin!, arrivalAirport],
            arrivalPoint: arrivalAirport,
            arrivalMinutes: g.row.arrivalMinutes!,
            calendar: [
              CalendarEntry(from: g.from, to: g.to, weekdays: g.weekdays)
            ],
          ),
      ],
    );
  }

  static const arrivalAirport = 'Aeroportul Suceava (SCV)';

  static _PdfRow? _parseRow(RegExpMatch m) {
    final weekday = _days[fold(m.group(1)!)];
    final dep = parseClock(m.group(3)!);
    final arr = parseClock(m.group(4)!);
    if (weekday == null || dep == null || arr == null) return null;

    // "<number> <COMPANY WORDS> [aircraft] <origin>"
    final tokens = m.group(2)!.split(' ');
    if (tokens.length < 4) return null;
    final number = '${tokens[0]} ${tokens[1]}'.replaceAll(RegExp(r'\s+'), ' ');
    if (!RegExp(r'^[A-Z0-9]{2} \d{2,4}$').hasMatch(number)) return null;
    var i = 2;
    final company = <String>[];
    while (i < tokens.length &&
        !RegExp(r'\d').hasMatch(tokens[i]) &&
        tokens[i] == tokens[i].toUpperCase()) {
      company.add(tokens[i]);
      i++;
    }
    if (i < tokens.length &&
        RegExp(r'^[A-Z]{1,2}\d{2,3}[A-Z0-9]?$').hasMatch(tokens[i])) {
      i++; // aircraft type: not used
    }
    final origin = tokens.sublist(i).join(' ');
    if (company.isEmpty || origin.isEmpty) return null;
    final plus = int.tryParse(m.group(5) ?? '') ?? 0;
    return _PdfRow(
      weekday: weekday,
      number: number,
      airline: _title(company.join(' ')),
      origin: origin,
      departure: dep,
      arrivalMinutes: arr + 1440 * plus,
    );
  }

  static void _attach(_PdfRow row, String label, RegExpMatch m) {
    final date = DateTime.utc(
      int.parse(m.group(3)!),
      int.parse(m.group(2)!),
      int.parse(m.group(1)!),
    );
    // Reject impossible dates that DateTime would roll over (31.02.2026).
    if (date.day != int.parse(m.group(1)!)) {
      row.unreadable = m.group(0);
      return;
    }
    if (label == 'from') {
      row.from = date;
    } else {
      row.until = date;
    }
  }

  static void _plausibility(List<_PdfRow> rows) {
    final byOrigin = <String, List<_PdfRow>>{};
    for (final row in rows) {
      if (row.invalid == null && row.origin != null) {
        byOrigin.putIfAbsent(row.origin!, () => []).add(row);
      }
    }
    for (final entry in byOrigin.entries) {
      if (entry.value.length < minRowsForCheck) continue;
      final durations = [for (final r in entry.value) r.duration]..sort();
      final median = durations[durations.length ~/ 2];
      for (final row in entry.value) {
        if ((row.duration - median).abs() > durationToleranceMinutes) {
          row.implausible =
              'durata ${_hm(row.duration)} diferă de cea obișnuită pe ruta '
              '${row.origin} (${_hm(median)}); posibilă eroare în sursă';
        }
      }
    }
  }

  static (DateTime, DateTime)? _periodOf(String text) {
    final m = _period.firstMatch(text);
    if (m == null) return null;
    final m1 = romanianMonths[fold(m.group(2)!)];
    final m2 = romanianMonths[fold(m.group(5)!)];
    if (m1 == null || m2 == null) return null;
    final from =
        DateTime.utc(int.parse(m.group(3)!), m1, int.parse(m.group(1)!));
    final to = DateTime.utc(int.parse(m.group(6)!), m2, int.parse(m.group(4)!));
    return to.isBefore(from) ? null : (from, to);
  }

  /// Period named in link text such as "... PENTRU PERIOADA 25 OCTOMBRIE 2026 –
  /// 27 MARTIE 2027 - SOSIRI", or null.
  static (DateTime, DateTime)? periodIn(String text) => _periodOf(text);

  static String _hm(int minutes) => '${minutes ~/ 60} h ${minutes % 60} min';

  static String _title(String s) => s
      .toLowerCase()
      .split(' ')
      .map((w) => w.isEmpty ? w : w[0].toUpperCase() + w.substring(1))
      .join(' ');
}

class _PdfRow {
  _PdfRow({
    required this.weekday,
    required this.number,
    required this.airline,
    required this.origin,
    required this.departure,
    required this.arrivalMinutes,
  }) : invalid = null;

  _PdfRow.invalid(this.invalid)
      : weekday = null,
        number = null,
        airline = null,
        origin = null,
        departure = null,
        arrivalMinutes = null;

  final String? invalid;
  final int? weekday;
  final String? number;
  final String? airline;
  final String? origin;
  final int? departure;
  final int? arrivalMinutes;

  DateTime? from;
  DateTime? until;
  String? unreadable;
  String? implausible;

  int get duration => arrivalMinutes! - departure!;

  String get label => '$number din $origin (${_dayName(weekday!)})';

  String? problem((DateTime, DateTime) period) {
    if (unreadable != null) return 'observație necunoscută «$unreadable»';
    if (implausible != null) return implausible;
    final effectiveFrom =
        from != null && from!.isAfter(period.$1) ? from! : period.$1;
    final effectiveTo =
        until != null && until!.isBefore(period.$2) ? until! : period.$2;
    if (effectiveFrom.isAfter(effectiveTo)) {
      return 'intervalul de date este gol';
    }
    return null;
  }

  static String _dayName(int weekday) => const [
        '',
        'luni',
        'marți',
        'miercuri',
        'joi',
        'vineri',
        'sâmbătă',
        'duminică',
      ][weekday];
}

class _Group {
  _Group(this.row, this.from, this.to);

  final _PdfRow row;
  final DateTime from;
  final DateTime to;
  final Set<int> weekdays = {};
}
