import 'dart:convert';

import 'package:shelf/shelf.dart';

import '../pipeline/pipeline.dart';

/// HTTP surface of the backend:
///
/// * `GET /v1/arrivals?from=&to=` normalized arrivals plus per-source status.
///   `from`/`to` are ISO-8601 instants with an offset; default is from 30
///   minutes ago to 24 hours ahead, capped at 72 hours.
/// * `GET /v1/sources` per-source status only.
/// * `GET /healthz` liveness.
///
/// Requests never fetch from the sources on the spot: the pipeline refreshes
/// them on its own schedule and a request only reads what it holds (the first
/// request after start waits for the initial load).
Handler buildHandler(TransportPipeline pipeline, {DateTime Function()? now}) {
  final clock = now ?? DateTime.now;
  const maxSpan = Duration(hours: 72);

  Response json(Object body, {int status = 200}) => Response(
        status,
        body: jsonEncode(body),
        headers: {
          'content-type': 'application/json; charset=utf-8',
          'cache-control': 'public, max-age=60',
        },
      );

  return (Request request) async {
    if (request.method != 'GET') {
      return json({'error': 'method not allowed'}, status: 405);
    }
    switch (request.url.path) {
      case 'healthz':
        return json({'ok': true});
      case 'v1/arrivals':
      case 'v1/sources':
        final current = clock().toUtc();
        final fromParam = request.url.queryParameters['from'];
        final toParam = request.url.queryParameters['to'];
        final from = fromParam == null
            ? current.subtract(const Duration(minutes: 30))
            : _instant(fromParam);
        final to = toParam == null
            ? current.add(const Duration(hours: 24))
            : _instant(toParam);
        if (from == null || to == null || !to.isAfter(from)) {
          return json({
            'error':
                'from and to must be ISO-8601 instants with an offset, with to after from',
          }, status: 400);
        }
        if (to.difference(from) > maxSpan) {
          return json({'error': 'the window may not exceed 72 hours'},
              status: 400);
        }
        await pipeline.ensureFresh();
        final snapshot = pipeline.arrivals(from: from, to: to);
        return json(
          request.url.path == 'v1/sources'
              ? {
                  'sources': [for (final s in snapshot.sources) s.toJson()]
                }
              : snapshot.toJson(),
        );
      default:
        return json({'error': 'not found'}, status: 404);
    }
  };
}

DateTime? _instant(String value) {
  if (!RegExp(r'(Z|[+-]\d{2}:?\d{2})$').hasMatch(value)) return null;
  return DateTime.tryParse(value)?.toUtc();
}

/// Adds CORS headers for one allowed browser origin (or `*`), and answers
/// `OPTIONS` preflights. Off unless configured: for testing the API from a
/// browser page such as Swagger UI served on another port. The mobile app does
/// not need it.
Handler withCors(Handler inner, String allowOrigin) {
  final headers = {
    'access-control-allow-origin': allowOrigin,
    if (allowOrigin != '*') 'vary': 'Origin',
  };
  return (Request request) async {
    if (request.method == 'OPTIONS') {
      return Response(
        204,
        headers: {
          ...headers,
          'access-control-allow-methods': 'GET, OPTIONS',
          'access-control-allow-headers': 'accept, content-type',
          'access-control-max-age': '600',
        },
      );
    }
    final response = await inner(request);
    return response.change(headers: headers);
  };
}

/// Whether [value] is acceptable for `CORS_ALLOW_ORIGIN`: `*`, or a bare origin
/// such as `http://127.0.0.1:8081` (scheme, host, optional port, no path).
bool isValidCorsOrigin(String value) {
  if (value == '*') return true;
  final uri = Uri.tryParse(value);
  return uri != null &&
      (uri.scheme == 'http' || uri.scheme == 'https') &&
      uri.host.isNotEmpty &&
      (uri.path.isEmpty) &&
      !uri.hasQuery &&
      !uri.hasFragment &&
      uri.userInfo.isEmpty;
}
