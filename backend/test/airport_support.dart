import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:suceava_alerts_backend/suceava_alerts_backend.dart';

String fixtureText(String name) =>
    File('test/fixtures/$name').readAsStringSync();

final pageUrl = Uri.parse('https://aeroportsuceava.ro/ro/2016-01-29-10-35-08');
const winterPdfPath = '/images/example/SOSIRI_IARNA.pdf';

/// Stands in for `pdftotext`: returns the text the real tool produces for the
/// winter timetable when it is handed the fake PDF the network serves.
class FixtureExtractor implements PdfTextExtractor {
  FixtureExtractor({String? text})
      : text = text ?? fixtureText('airport_winter_arrivals.txt');

  final String text;

  @override
  Future<String> extract(List<int> pdfBytes) async {
    if (utf8
        .decode(pdfBytes, allowMalformed: true)
        .contains('winter fixture')) {
      return text;
    }
    throw const PdfExtractionException('not the fixture PDF');
  }
}

/// An extractor that behaves as if `pdftotext` is not installed.
class MissingToolExtractor implements PdfTextExtractor {
  @override
  Future<String> extract(List<int> pdfBytes) async =>
      throw const PdfExtractionException(
        'pdftotext nu este instalat pe server; orarul din PDF nu poate fi citit.',
      );
}

/// A fake airport website plus the adapter wired to it, with a controllable clock.
class AirportRig {
  AirportRig({String? page, this.pdfStatus = 200, PdfTextExtractor? extractor})
      : page = page ?? fixtureText('airport_page.html'),
        extractor = extractor ?? FixtureExtractor();

  final String page;
  final int pdfStatus;
  final PdfTextExtractor extractor;
  final List<Uri> requests = [];

  List<String> get fetchedPaths => [
        for (final u in requests)
          if (u.path != '/robots.txt') u.path,
      ];

  late final MockClient client = MockClient((request) async {
    requests.add(request.url);
    if (request.url.path == '/robots.txt') return http.Response('', 404);
    if (request.url.toString() == pageUrl.toString()) {
      return http.Response.bytes(utf8.encode(page), 200);
    }
    if (request.url.path == winterPdfPath) {
      return pdfStatus == 200
          ? http.Response.bytes(utf8.encode('%PDF-1.7 winter fixture'), 200)
          : http.Response('unavailable', pdfStatus);
    }
    return http.Response('not found', 404);
  });

  AirportTimetableAdapter get adapter =>
      AirportTimetableAdapter(pdfExtractor: extractor);

  Future<AdapterLoad> load(DateTime now) => adapter.load(
        PoliteFetcher(
            userAgent: 'test',
            client: client,
            now: () => now,
            sleep: (_) async {}),
        now,
      );

  /// Dated services from a load, inside `[from, to]`.
  List<NormalizedService> services(
          AdapterLoad load, DateTime from, DateTime to) =>
      expandPatterns(
        source: adapter.descriptor,
        patterns: load.patterns,
        from: from,
        to: to,
        fetchedAt: load.fetchedAt ?? from,
      );
}
