import 'package:html/dom.dart';
import 'package:html/parser.dart' as html;

import '../fetch/polite_fetcher.dart';
import '../model/model.dart';
import 'source_adapter.dart';

/// Coach arrivals from the airport's "Transfer aeroport" page: the daily
/// Cernăuți - Suceava - airport (Salcea) service, published as two route
/// tables for each direction.
///
/// Reading rules:
/// * Each table row is one leg "A > B" with departure and arrival clock
///   times. A leg ending in "Suceava" is an arrival at the bus station; a leg
///   ending in "Salcea" is an arrival at the airport. All other legs are
///   ignored.
/// * The route is every station of the table, in order.
/// * The page says the service runs daily ("2 curse zilnice") but publishes no
///   validity end, and does not say which of the two operators runs which
///   trip; both operators are named.
/// * Cernăuți (Ukraine) and Romania share the same clock time zone, so times
///   are read as Bucharest time.
class AirportTransferAdapter extends SourceAdapter {
  AirportTransferAdapter({Uri? pageUrl})
      : pageUrl = pageUrl ??
            Uri.parse(
              'https://www.aeroportsuceava.ro/ro/info-pasageri/transfer-aeroport',
            );

  final Uri pageUrl;

  static const String sourceId = 'scv-airport-transfer';
  static const operators =
      'NICOLMIT S.R.L. / PP "NOV TRABS-AVTO" (operatorul fiecărei curse nu '
      'este precizat)';
  static const busStation = 'Autogara Suceava';
  static const airportStop = 'Aeroportul Suceava (Salcea)';

  @override
  SourceDescriptor get descriptor => SourceDescriptor(
        id: sourceId,
        name: 'Transfer Cernăuți - Suceava - Aeroport',
        kind: TransportKind.coach,
        url: pageUrl.toString(),
      );

  @override
  Future<AdapterLoad> load(PoliteFetcher fetcher, DateTime now) async {
    final result = await fetcher.get(pageUrl);
    final patterns = parse(result.text);
    return AdapterLoad(
      connection: SourceConnection.scheduledOnly,
      message: 'Orar programat publicat de aeroport. Pagina nu are dată de '
          'valabilitate; se presupune zilnic. Verificați la dispeceratul '
          'operatorului.',
      patterns: patterns,
      fetchedAt: result.fetchedAt,
    );
  }

  /// Throws [FormatException] if no route table is found.
  static List<SchedulePattern> parse(String body) {
    final doc = html.parse(body);
    final patterns = <SchedulePattern>[];
    var routeTables = 0;

    for (final table in doc.querySelectorAll('table')) {
      final rows = table.querySelectorAll('tr');
      if (rows.isEmpty) continue;
      final title = tidy(rows.first.querySelector('td, th')?.text ?? '');
      if (!fold(title).startsWith('ruta')) continue;
      routeTables++;

      final legs = <({String from, String to, int? depart, int? arrive})>[];
      for (final row in rows.skip(1)) {
        final cells = [
          for (final c in row.querySelectorAll('td')) tidy(c.text)
        ];
        if (cells.length < 3 || !cells.first.contains('>')) continue;
        final parts = cells.first.split('>');
        if (parts.length != 2) continue;
        legs.add((
          from: tidy(parts[0]),
          to: tidy(parts[1]),
          depart: parseClock(cells[1]),
          arrive: parseClock(cells[2]),
        ));
      }
      if (legs.isEmpty) continue;

      final stations = [legs.first.from, for (final l in legs) l.to];
      final direction = _direction(table);
      final label = title.replaceAll(RegExp(r'\s+'), ' ');
      for (final leg in legs) {
        final String point;
        if (fold(leg.to) == 'suceava') {
          point = busStation;
        } else if (fold(leg.to) == 'salcea') {
          point = airportStop;
        } else {
          continue;
        }
        if (leg.arrive == null) continue;
        patterns.add(
          SchedulePattern(
            serviceNumber: '$direction ($label)',
            operatorName: operators,
            routeStops: stations,
            arrivalPoint: point,
            arrivalMinutes: leg.arrive!,
            calendar: [everyDay()],
          ),
        );
      }
    }
    if (routeTables == 0) {
      throw const FormatException('Nu s-au găsit tabele de rută.');
    }
    return patterns;
  }

  /// Names the service from the paragraph that precedes the table.
  static String _direction(Element table) {
    Element? p = table.previousElementSibling;
    var guard = 0;
    while (p != null && guard++ < 6) {
      final text = fold(tidy(p.text));
      if (text.contains('plecare din cernauti')) {
        return 'Transfer Cernăuți – Suceava – Aeroport';
      }
      if (text.contains('plecare din aeroport')) {
        return 'Transfer Aeroport – Suceava – Cernăuți';
      }
      p = p.previousElementSibling;
    }
    return 'Transfer Cernăuți – Suceava';
  }
}
