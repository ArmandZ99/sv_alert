import 'package:html/dom.dart';
import 'package:html/parser.dart' as html;

import '../fetch/polite_fetcher.dart';
import '../model/model.dart';
import 'source_adapter.dart';

/// Coach arrivals in Suceava from TASA (Transporturi Auto Suceava), read from
/// the operator's own route page.
///
/// What the page publishes, and so what is produced:
/// * route cards list departure and arrival times per direction. For each card
///   that ends in Suceava, every "Ore de sosire" time becomes an arrival. The
///   page does not publish intermediate stops for those directions, so the
///   route is just origin and Suceava: nothing is invented.
/// * per-route tables list stops with times. When Suceava is not the first row
///   the row gives the arrival at Suceava, with the real stop name and the
///   full list of localities.
/// * the page shows the seven weekday letters identically for every route and
///   no validity period, so the schedule is treated as daily and the status
///   message says that this is an assumption.
class TasaAdapter extends SourceAdapter {
  TasaAdapter({Uri? pageUrl})
      : pageUrl = pageUrl ?? Uri.parse('https://www.tasasuceava.ro/trasee/');

  final Uri pageUrl;

  static const String sourceId = 'tasa-suceava';
  static const operatorName = 'TASA (Transporturi Auto Suceava)';

  @override
  SourceDescriptor get descriptor => SourceDescriptor(
        id: sourceId,
        name: 'TASA Suceava - trasee',
        kind: TransportKind.coach,
        url: pageUrl.toString(),
      );

  @override
  Future<AdapterLoad> load(PoliteFetcher fetcher, DateTime now) async {
    final result = await fetcher.get(pageUrl);
    final patterns = parse(result.text);
    return AdapterLoad(
      connection: SourceConnection.scheduledOnly,
      message:
          'Orar programat publicat de operator. Pagina nu precizează zilele '
          'de circulație sau perioada de valabilitate: se presupune zilnic. '
          'Opririle intermediare apar doar unde operatorul le publică.',
      patterns: patterns,
      fetchedAt: result.fetchedAt,
    );
  }

  /// Throws [FormatException] if the page has neither route cards nor tables.
  static List<SchedulePattern> parse(String body) {
    final doc = html.parse(body);
    final cards = doc.querySelectorAll('article.route-card');
    final tables = doc.querySelectorAll('.tasa-ruta');
    if (cards.isEmpty && tables.isEmpty) {
      throw const FormatException('Nu s-au găsit trasee pe pagină.');
    }

    final patterns = <SchedulePattern>[];

    for (final card in cards) {
      final locations = card.querySelectorAll('.location');
      Element? from;
      Element? to;
      for (final loc in locations) {
        final label = fold(tidy(loc.querySelector('.label')?.text ?? ''));
        if (label == 'plecare') from = loc;
        if (label == 'sosire') to = loc;
      }
      if (from == null || to == null) continue;
      final toCity = tidy(to.querySelector('strong')?.text ?? '');
      if (fold(toCity) != 'suceava') continue;
      final fromCity = tidy(from.querySelector('strong')?.text ?? '');
      final stop = _firstLine(to.querySelector('p'));
      if (fromCity.isEmpty) continue;

      for (final box in card.querySelectorAll('.time-box')) {
        final label = fold(tidy(box.querySelector('.time-label')?.text ?? ''));
        if (!label.contains('sosire')) continue;
        for (final t in box.querySelectorAll('.time')) {
          final minutes = parseClock(t.text);
          if (minutes == null) continue;
          patterns.add(
            SchedulePattern(
              serviceNumber: 'TASA $fromCity – Suceava',
              operatorName: operatorName,
              routeStops: [fromCity, 'Suceava'],
              arrivalPoint: _point(stop),
              arrivalMinutes: minutes,
              calendar: [everyDay()],
            ),
          );
        }
      }
    }

    for (final route in tables) {
      final rows = <({String city, String stop, int? minutes})>[];
      for (final tr in route.querySelectorAll('tbody tr')) {
        final city = tidy(tr.querySelector('.tasa-localitate')?.text ?? '');
        final stop = tidy(tr.querySelector('.tasa-statie')?.text ?? '');
        final minutes =
            parseClock(tr.querySelector('.tasa-ora-cell')?.text ?? '');
        if (city.isEmpty) continue;
        rows.add((city: city, stop: stop, minutes: minutes));
      }
      final at = rows.indexWhere((r) => fold(r.city) == 'suceava');
      // Suceava as the first stop is a departure, not an arrival.
      if (at <= 0 || rows[at].minutes == null) continue;
      final cities = [for (final r in rows) r.city];
      patterns.add(
        SchedulePattern(
          serviceNumber: 'TASA ${cities.first} – ${cities.last}',
          operatorName: operatorName,
          routeStops: cities,
          arrivalPoint: _point(rows[at].stop),
          arrivalMinutes: rows[at].minutes!,
          calendar: [everyDay()],
        ),
      );
    }
    return patterns;
  }

  static String _firstLine(Element? p) {
    if (p == null) return '';
    // `<p>Autogara Nouă TASA<br>Str. ...</p>`: keep only the stop name.
    final first = p.nodes.firstWhere(
      (n) => n.nodeType == Node.TEXT_NODE && tidy(n.text ?? '').isNotEmpty,
      orElse: () => Text(''),
    );
    return tidy(first.text ?? '');
  }

  static String _point(String stop) {
    var name = stop.replaceAll(RegExp(r'\s+Invest Imobiliare SRL$'), '').trim();
    if (name.isEmpty) name = 'Autogara TASA';
    return '$name, Suceava';
  }
}
