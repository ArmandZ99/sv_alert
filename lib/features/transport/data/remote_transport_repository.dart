import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import 'sources/normalized_arrivals_parser.dart';
import 'sources/source_status.dart';
import 'transport_repository.dart';

/// Reads arrivals from the ingestion backend (`GET /v1/arrivals`). All
/// fetching, parsing and polling of the real sources happens there; the app
/// only receives the normalized contract and validates it.
class RemoteTransportRepository implements TransportRepository {
  RemoteTransportRepository({
    required this.baseUrl,
    http.Client? client,
    this.timeout = const Duration(seconds: 120),
    this.maxAttempts = 2,
    this.retryDelay = const Duration(seconds: 3),
    this.lookBehind = const Duration(minutes: 30),
    this.lookAhead = const Duration(hours: 24),
    DateTime Function()? now,
    void Function(String message)? logger,
  }) : assert(maxAttempts >= 1),
       _client = client ?? http.Client(),
       _now = now ?? DateTime.now,
       _logger = logger ?? (kDebugMode ? debugPrint : null);

  final Uri baseUrl;

  /// Per attempt. Measured on the deployed Render Free service: the first
  /// request after idle took 83 s to be answered, and the sources then needed
  /// about 45 s more to load. The server holds the connection while it wakes,
  /// so one long attempt is better than several short ones that each abandon
  /// it. Bounded: at most [maxAttempts] x this, plus the pauses.
  final Duration timeout;

  /// Total tries including the first; waits [retryDelay] x n between them.
  final int maxAttempts;
  final Duration retryDelay;
  final void Function(String message)? _logger;
  final Duration lookBehind;
  final Duration lookAhead;
  final http.Client _client;
  final DateTime Function() _now;

  /// `<base>/v1/arrivals?from=...&to=...` keeping any path prefix of [baseUrl].
  Uri get arrivalsUrl {
    final prefix = baseUrl.path.endsWith('/')
        ? baseUrl.path.substring(0, baseUrl.path.length - 1)
        : baseUrl.path;
    final now = _now().toUtc();
    return baseUrl.replace(
      path: '$prefix/v1/arrivals',
      queryParameters: {
        'from': now.subtract(lookBehind).toIso8601String(),
        'to': now.add(lookAhead).toIso8601String(),
      },
    );
  }

  /// Fetches the arrivals, retrying a few times when the failure may be
  /// transient: no answer in time, no connection, or a gateway error while the
  /// hosted service is waking up. Anything else (other HTTP errors, unreadable
  /// or incompatible JSON) is final, since asking again returns the same.
  @override
  Future<TransportSnapshot> fetchUpcomingArrivals() async {
    TransportFetchException? last;
    for (var attempt = 1; attempt <= maxAttempts; attempt++) {
      try {
        return await _fetchOnce(attempt);
      } on _TransientFailure catch (e) {
        last = e.error;
        if (attempt < maxAttempts) {
          _log('retrying in ${retryDelay.inSeconds * attempt}s');
          await Future<void>.delayed(retryDelay * attempt);
        }
      }
    }
    throw last!;
  }

  Future<TransportSnapshot> _fetchOnce(int attempt) async {
    final url = arrivalsUrl;
    _log(
      'GET ${url.origin}${url.path} '
      'from=${url.queryParameters['from']} to=${url.queryParameters['to']} '
      '(UTC, offset Z; attempt $attempt of $maxAttempts)',
    );
    final http.Response response;
    try {
      response = await _client
          .get(url, headers: {'accept': 'application/json'})
          .timeout(timeout);
    } on TimeoutException {
      _log('no answer within ${timeout.inSeconds}s');
      throw const _TransientFailure(
        TransportFetchException('Serverul de date nu a răspuns la timp.'),
      );
    } on http.ClientException catch (e) {
      _log('connection error: ${e.message}');
      throw const _TransientFailure(
        TransportFetchException('Nu s-a putut contacta serverul de date.'),
      );
    } on Object catch (e) {
      // Other transport errors (for example a TLS failure) are not retried.
      _log('request failed: ${e.runtimeType}');
      throw const TransportFetchException(
        'Nu s-a putut contacta serverul de date.',
      );
    }

    _log(
      'HTTP ${response.statusCode} ${response.headers['content-type'] ?? ''} '
      '${response.bodyBytes.length} bytes',
    );
    if (response.statusCode != 200) {
      final error = TransportFetchException(
        'Serverul de date a răspuns cu eroarea ${response.statusCode}.',
      );
      // 502/503/504: a hosted service that is still starting.
      if (const {502, 503, 504}.contains(response.statusCode)) {
        throw _TransientFailure(error);
      }
      throw error;
    }

    final Object? json;
    try {
      json = jsonDecode(utf8.decode(response.bodyBytes));
    } on FormatException catch (e) {
      _log('invalid JSON: ${e.message}');
      throw const TransportFetchException(
        'Răspuns necitibil de la serverul de date.',
      );
    }
    try {
      final parsed = NormalizedArrivalsParser.parse(json);
      final snapshot = parsed.snapshot;
      _logOutcome(snapshot, parsed.rejected);
      return snapshot;
    } on TransportFetchException catch (e) {
      _log('incompatible response: ${e.message}');
      rethrow;
    } on Object catch (e) {
      _log('parser failure: ${e.runtimeType}');
      throw const TransportFetchException(
        'Răspuns neașteptat de la serverul de date.',
      );
    }
  }

  /// Tells apart: data received, a valid answer with no arrivals, a valid
  /// answer where the server's own sources failed, and records the parser
  /// rejected.
  void _logOutcome(TransportSnapshot snapshot, List<String> rejected) {
    final parsedCount = snapshot.services.length;
    _log(
      'records: ${parsedCount + rejected.length} raw, $parsedCount parsed, '
      '${rejected.length} rejected',
    );
    for (final reason in rejected.take(3)) {
      _log('rejected $reason');
    }
    final failing = [
      for (final s in snapshot.sources)
        if (s.connection == SourceConnection.unavailable) s,
    ];
    for (final s in failing) {
      final message = s.message.length > 160
          ? '${s.message.substring(0, 160)}...'
          : s.message;
      _log('source ${s.id}: ${s.connection.name} - $message');
    }
    if (parsedCount > 0) {
      _log('ok: $parsedCount services');
    } else if (snapshot.sources.isNotEmpty &&
        snapshot.sources.every((s) => !s.providesData)) {
      _log(
        'ok but empty: the server has no usable source '
        '(${failing.length} of ${snapshot.sources.length} failed)',
      );
    } else {
      _log('ok but empty: sources are working, no arrivals in this window');
    }
  }

  void _log(String message) => _logger?.call('[api] $message');

  void close() => _client.close();
}

/// A failure worth another attempt.
class _TransientFailure implements Exception {
  const _TransientFailure(this.error);
  final TransportFetchException error;
}
