// Dev tool: runs the parsers on local copies of the source files and prints
// what they find. Makes no network requests, so it is safe to run repeatedly
// when a site changes its layout.
//
//   dart run tool/inspect_sources.dart --airport a.html --tasa t.html \
//       --transfer x.html --rail-xml sntfc.xml
//
// Airport winter arrivals PDF (needs `pdftotext` on the PATH), or text that
// `pdftotext -raw -enc UTF-8 file.pdf out.txt` already produced:
//   dart run tool/inspect_sources.dart --airport-pdf winter.pdf
//   dart run tool/inspect_sources.dart --airport-pdf-text out.txt
import 'dart:io';

import 'package:suceava_alerts_backend/suceava_alerts_backend.dart';

Future<void> main(List<String> args) async {
  String? arg(String name) {
    final i = args.indexOf('--$name');
    return i >= 0 && i + 1 < args.length ? args[i + 1] : null;
  }

  final now = DateTime.now().toUtc();
  final from = now.subtract(const Duration(minutes: 30));
  final to = now.add(const Duration(hours: 24));

  void report(
      String title, SourceDescriptor d, List<SchedulePattern> patterns) {
    final services = expandPatterns(
      source: d,
      patterns: patterns,
      from: from,
      to: to,
      fetchedAt: now,
    );
    stdout.writeln('== $title: ${patterns.length} patterns, '
        '${services.length} services in the next 24 h');
    for (final s in services.take(40)) {
      final t = BucharestTime.of(s.scheduledArrival);
      final hh = t.hour.toString().padLeft(2, '0');
      final mm = t.minute.toString().padLeft(2, '0');
      stdout.writeln('   $hh:$mm  ${s.serviceNumber.padRight(34)} '
          '${s.routeStops.first} -> ${s.routeStops.last}  @ ${s.arrivalPoint}');
    }
  }

  final airport = arg('airport');
  if (airport != null) {
    final p = AirportTimetableAdapter.parse(File(airport).readAsStringSync());
    stdout.writeln('airport validity: ${p.validFrom} .. ${p.validTo}');
    report(
        'airport timetable', AirportTimetableAdapter().descriptor, p.patterns);
  }
  Future<void> reportPdf(String text) async {
    final p = AirportPdfTimetableParser.parse(text);
    stdout.writeln('airport PDF validity: ${p.validFrom} .. ${p.validTo}');
    stdout.writeln(
        '${p.patterns.length} patterns, ${p.rejected.length} rejected rows:');
    for (final r in p.rejected) {
      stdout.writeln('   REJECTED $r');
    }
    report('airport PDF', AirportTimetableAdapter().descriptor, p.patterns);
  }

  final airportPdf = arg('airport-pdf');
  if (airportPdf != null) {
    final text =
        await PdftotextExtractor().extract(File(airportPdf).readAsBytesSync());
    await reportPdf(text);
  }
  final airportPdfText = arg('airport-pdf-text');
  if (airportPdfText != null) {
    await reportPdf(File(airportPdfText).readAsStringSync());
  }
  final tasa = arg('tasa');
  if (tasa != null) {
    report('TASA', TasaAdapter().descriptor,
        TasaAdapter.parse(File(tasa).readAsStringSync()));
  }
  final transfer = arg('transfer');
  if (transfer != null) {
    report('airport transfer', AirportTransferAdapter().descriptor,
        AirportTransferAdapter.parse(File(transfer).readAsStringSync()));
  }
  final rail = arg('rail-xml');
  if (rail != null) {
    final p = await RailTimetableAdapter.parse(
      File(rail).readAsStringSync(),
      operatorName: 'test',
      sourceUrl: 'https://example.invalid',
    );
    stdout.writeln('rail: ${p.trainsSeen} trains, valid ${p.validFrom} .. '
        '${p.validTo}, exported ${p.exportDate}, skipped calendars ${p.skippedCalendars}');
    report('rail', RailTimetableAdapter(datasets: const []).descriptor,
        p.patterns);
  }
}
