import 'dart:async';
import 'dart:convert';
import 'dart:io';

/// The PDF could not be turned into text. The message is safe to show.
class PdfExtractionException implements Exception {
  const PdfExtractionException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Turns PDF bytes into text in content-stream order, one table row per line.
///
/// Kept behind an interface so tests need no PDF tool, and so a different
/// extractor can replace the command-line one.
abstract interface class PdfTextExtractor {
  Future<String> extract(List<int> pdfBytes);
}

/// Extracts text with the `pdftotext` command (Xpdf or Poppler) using
/// `-raw -enc UTF-8`. Raw mode keeps each table row's cells together, which
/// the airport timetable parser relies on; the default and `-layout` modes
/// misalign cells that are vertically centred in tall rows.
///
/// The tool must be installed on the host (`poppler-utils` on Debian/Ubuntu).
/// Verified with Xpdf 4.06; verify Poppler's `-raw` order on your host with
/// `dart run tool/inspect_sources.dart --airport-pdf-text` before relying on it.
class PdftotextExtractor implements PdfTextExtractor {
  PdftotextExtractor({
    this.executable = 'pdftotext',
    this.timeout = const Duration(seconds: 30),
  });

  final String executable;
  final Duration timeout;

  @override
  Future<String> extract(List<int> pdfBytes) async {
    // A PDF starts with "%PDF-". Anything else (an HTML error page, say) is
    // not worth handing to a tool.
    if (pdfBytes.length < 5 ||
        latin1.decode(pdfBytes.sublist(0, 5)) != '%PDF-') {
      throw const PdfExtractionException('Fișierul primit nu este un PDF.');
    }

    final dir = await Directory.systemTemp.createTemp('airport_pdf_');
    try {
      final file = File('${dir.path}${Platform.pathSeparator}timetable.pdf');
      await file.writeAsBytes(pdfBytes, flush: true);
      final ProcessResult result;
      try {
        result = await Process.run(
          executable,
          ['-raw', '-enc', 'UTF-8', file.path, '-'],
          stdoutEncoding: utf8,
          stderrEncoding: utf8,
        ).timeout(timeout);
      } on ProcessException {
        throw const PdfExtractionException(
          'pdftotext nu este instalat pe server; orarul din PDF nu poate fi citit.',
        );
      } on TimeoutException {
        throw const PdfExtractionException('pdftotext nu a terminat la timp.');
      }
      if (result.exitCode != 0) {
        throw const PdfExtractionException('pdftotext nu a putut citi PDF-ul.');
      }
      return result.stdout as String;
    } finally {
      try {
        await dir.delete(recursive: true);
      } on FileSystemException {
        // Temporary files are cleaned by the OS eventually.
      }
    }
  }
}
