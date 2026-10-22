import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import 'sources/normalized_arrivals_parser.dart';
import 'transport_repository.dart';

/// Reads arrivals from the ingestion backend (`GET /v1/arrivals`). All
/// fetching, parsing and polling of the real sources happens there; the app
/// only receives the normalized contract and validates it.
class RemoteTransportRepository implements TransportRepository {
  RemoteTransportRepository({
    required this.baseUrl,
    http.Client? client,
    this.timeout = const Duration(seconds: 40),
    this.maxAttempts = 3,
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

  /// Per attempt. A free hosted service can take around a minute to wake up,
  /// then needs a while to load its sources, so this is generous but bounded.
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
    _log('GET ${url.origin}${url.path} (attempt $attempt of $maxAttempts)');
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

    if (response.statusCode != 200) {
      _log('HTTP ${response.statusCode}');
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
      final snapshot = NormalizedArrivalsParser.parse(json).snapshot;
      _log('ok: ${snapshot.services.length} services');
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

  void _log(String message) => _logger?.call('[api] $message');

  void close() => _client.close();
}

/// A failure worth another attempt.
class _TransientFailure implements Exception {
  const _TransientFailure(this.error);
  final TransportFetchException error;
}

/// Uses [primary] (the backend) and falls back to [fallback] (the demo data)
/// only when the primary cannot be reached or read. The fallback snapshot says
/// why, and its services stay individually marked as demo data.
class FallbackTransportRepository implements TransportRepository {
  const FallbackTransportRepository({
    required this.primary,
    required this.fallback,
  });

  final TransportRepository primary;
  final TransportRepository fallback;

  static const String reason =
      'Datele reale nu au putut fi încărcate; se afișează date demonstrative.';

  @override
  Future<TransportSnapshot> fetchUpcomingArrivals() async {
    try {
      return await primary.fetchUpcomingArrivals();
    } on TransportFetchException {
      final demo = await fallback.fetchUpcomingArrivals();
      return TransportSnapshot(
        services: demo.services,
        fetchedAt: demo.fetchedAt,
        isMock: demo.isMock,
        sources: demo.sources,
        degradedReason: reason,
      );
    }
  }
}
