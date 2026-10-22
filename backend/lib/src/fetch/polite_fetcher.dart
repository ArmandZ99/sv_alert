import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import 'robots.dart';

typedef Now = DateTime Function();

/// The request was not made because robots.txt forbids it, the site asked us
/// to back off, or the fetch failed. The message is safe to show.
class FetchException implements Exception {
  const FetchException(this.message, {this.blocked = false});

  final String message;

  /// True when access is refused by policy (robots.txt, 401/403, rate limit),
  /// as opposed to a transient failure. Blocked sources are never retried by
  /// getting around the block.
  final bool blocked;

  @override
  String toString() => message;
}

/// What one HTTP answer looked like, kept so a source that cannot be read can
/// say what it actually received (an error page, a bot-check page, a redirect
/// to a consent page...) instead of only "structure changed".
class ResponseInfo {
  const ResponseInfo({
    required this.url,
    required this.status,
    required this.contentType,
    required this.bytes,
    this.title,
  });

  /// Host and path only: no query string, which could carry a token.
  final String url;
  final int status;
  final String? contentType;
  final int bytes;

  /// The HTML `<title>`, shortened, when there is one.
  final String? title;

  factory ResponseInfo.of(Uri url, http.Response response) {
    final type = response.headers['content-type'];
    String? title;
    if (type == null || type.contains('html')) {
      final head = utf8.decode(
        response.bodyBytes.length > 8192
            ? response.bodyBytes.sublist(0, 8192)
            : response.bodyBytes,
        allowMalformed: true,
      );
      final match = RegExp(
        r'<title[^>]*>([^<]{1,200})',
        caseSensitive: false,
      ).firstMatch(head);
      final text = match?.group(1)?.replaceAll(RegExp(r'\s+'), ' ').trim();
      if (text != null && text.isNotEmpty) {
        title = text.length > 80 ? '${text.substring(0, 80)}...' : text;
      }
    }
    return ResponseInfo(
      url: '${url.host}${url.path}',
      status: response.statusCode,
      contentType: type?.split(';').first.trim(),
      bytes: response.bodyBytes.length,
      title: title,
    );
  }

  @override
  String toString() =>
      '$url: HTTP $status, ${contentType ?? 'tip necunoscut'}, $bytes octeți'
      '${title == null ? '' : ', titlu "$title"'}';
}

class FetchResult {
  const FetchResult({
    required this.bytes,
    required this.fetchedAt,
    required this.fromCache,
    this.etag,
    this.lastModified,
  });

  final List<int> bytes;

  /// When the content was last confirmed by the server.
  final DateTime fetchedAt;
  final bool fromCache;
  final String? etag;
  final DateTime? lastModified;

  String get text => utf8.decode(bytes, allowMalformed: true);
}

/// HTTP client for public pages and files, built to be a good citizen:
///
/// * identifies itself with a descriptive User-Agent and contact;
/// * obeys robots.txt (a missing file allows everything; an unreadable one
///   forbids everything) and its Crawl-delay;
/// * waits [minInterval] between requests to the same host;
/// * caches responses in memory for [ttl] (or the server's `max-age`, if
///   longer), then revalidates with `If-None-Match` / `If-Modified-Since`;
/// * backs off on 429/503 using `Retry-After`, and treats 401/403 as a block;
/// * never solves CAPTCHAs, logs in or retries around a refusal.
class PoliteFetcher {
  PoliteFetcher({
    required this.userAgent,
    http.Client? client,
    Now? now,
    this.minInterval = const Duration(seconds: 5),
    this.ttl = const Duration(hours: 6),
    this.timeout = const Duration(seconds: 30),
    this.maxBytes = 40 * 1024 * 1024,
    Future<void> Function(Duration)? sleep,
  })  : _client = client ?? http.Client(),
        _now = now ?? DateTime.now,
        _sleep = sleep ?? Future<void>.delayed;

  final String userAgent;
  final Duration minInterval;
  final Duration ttl;
  final Duration timeout;
  final int maxBytes;

  final http.Client _client;
  final Now _now;
  final Future<void> Function(Duration) _sleep;

  final Map<String, _Robots> _robots = {};
  final Map<String, DateTime> _lastRequest = {};
  final Map<String, DateTime> _backoffUntil = {};
  final Map<Uri, _Cached> _cache = {};

  /// The answers received since the last [clearResponseLog], for diagnostics.
  final List<ResponseInfo> responseLog = [];

  void clearResponseLog() => responseLog.clear();

  /// One line per recent answer, or an empty string when none was received.
  String describeResponses() => responseLog.map((r) => r.toString()).join('; ');

  Future<FetchResult> get(Uri url, {Duration? maxAge}) async {
    final age = maxAge ?? ttl;
    final cached = _cache[url];
    if (cached != null &&
        _now().difference(cached.checkedAt) < cached.freshFor(age)) {
      return cached.toResult(fromCache: true);
    }

    final host = url.host;
    final until = _backoffUntil[host];
    if (until != null && _now().isBefore(until)) {
      throw const FetchException(
        'Site-ul a cerut să nu mai fie interogat o perioadă.',
        blocked: true,
      );
    }

    final rules = await _rulesFor(url);
    final path = url.hasQuery ? '${url.path}?${url.query}' : url.path;
    if (rules.unreadable != null) {
      throw FetchException(
        'robots.txt nu a putut fi citit (${rules.unreadable}); prin precauție '
        'sursa nu este accesată.',
        blocked: true,
      );
    }
    if (!rules.rules.isAllowed(path.isEmpty ? '/' : path)) {
      throw const FetchException(
        'robots.txt nu permite accesul automat la această adresă.',
        blocked: true,
      );
    }

    await _throttle(host, rules.rules.crawlDelay);

    final headers = {
      'user-agent': userAgent,
      'accept': '*/*',
      if (cached?.etag != null) 'if-none-match': cached!.etag!,
      if (cached?.lastModifiedRaw != null)
        'if-modified-since': cached!.lastModifiedRaw!,
    };

    final response = await _send(url, headers);
    _lastRequest[host] = _now();
    responseLog.add(ResponseInfo.of(url, response));

    if (response.statusCode == 304 && cached != null) {
      cached.checkedAt = _now();
      return cached.toResult(fromCache: true);
    }
    _checkStatus(host, response);

    final entry = _Cached(
      bytes: response.bodyBytes,
      checkedAt: _now(),
      etag: response.headers['etag'],
      lastModifiedRaw: response.headers['last-modified'],
      serverMaxAge: _maxAge(response.headers['cache-control']),
    );
    _cache[url] = entry;
    return entry.toResult(fromCache: false);
  }

  Future<http.Response> _send(Uri url, Map<String, String> headers) async {
    try {
      final streamed = await _client
          .send(http.Request('GET', url)..headers.addAll(headers))
          .timeout(timeout);
      final length = streamed.contentLength;
      if (length != null && length > maxBytes) {
        throw const FetchException('Răspunsul sursei este prea mare.');
      }
      return await http.Response.fromStream(streamed).timeout(timeout);
    } on TimeoutException {
      throw const FetchException('Sursa nu a răspuns la timp.');
    } on http.ClientException {
      throw const FetchException('Nu s-a putut contacta sursa.');
    }
  }

  void _checkStatus(String host, http.Response response) {
    final code = response.statusCode;
    if (code >= 200 && code < 300) return;
    if (code == 429 || code == 503) {
      final retry = int.tryParse(response.headers['retry-after'] ?? '');
      _backoffUntil[host] = _now().add(
        Duration(seconds: (retry ?? 900).clamp(60, 86400)),
      );
      throw const FetchException(
        'Sursa limitează cererile; se așteaptă înainte de o nouă încercare.',
        blocked: true,
      );
    }
    if (code == 401 || code == 403) {
      throw const FetchException(
        'Sursa refuză accesul automat.',
        blocked: true,
      );
    }
    throw FetchException('Sursa a răspuns cu eroarea HTTP $code.');
  }

  Future<_Robots> _rulesFor(Uri url) async {
    final origin = '${url.scheme}://${url.authority}';
    final cached = _robots[origin];
    if (cached != null &&
        _now().difference(cached.fetchedAt) < const Duration(hours: 24)) {
      return cached;
    }
    final robotsUrl = Uri.parse('$origin/robots.txt');
    RobotsRules rules;
    String? unreadable;
    try {
      await _throttle(url.host, null);
      final response = await _send(robotsUrl, {'user-agent': userAgent});
      _lastRequest[url.host] = _now();
      final code = response.statusCode;
      if (code == 404 || code == 410) {
        rules = RobotsRules.allowAll();
      } else if (code >= 200 && code < 300) {
        rules = RobotsRules.parse(
          utf8.decode(response.bodyBytes, allowMalformed: true),
          userAgent: userAgent,
        );
      } else {
        rules = RobotsRules.disallowAll();
        unreadable = 'HTTP $code';
      }
    } on FetchException catch (e) {
      rules = RobotsRules.disallowAll();
      unreadable = e.message;
    }
    return _robots[origin] = _Robots(rules, _now(), unreadable: unreadable);
  }

  Future<void> _throttle(String host, Duration? crawlDelay) async {
    final last = _lastRequest[host];
    if (last == null) return;
    final wait = (crawlDelay != null && crawlDelay > minInterval)
        ? crawlDelay
        : minInterval;
    final remaining = wait - _now().difference(last);
    if (remaining > Duration.zero) await _sleep(remaining);
  }

  static Duration? _maxAge(String? cacheControl) {
    if (cacheControl == null) return null;
    final match = RegExp(r'max-age=(\d+)').firstMatch(cacheControl);
    final seconds = match == null ? null : int.tryParse(match.group(1)!);
    return seconds == null ? null : Duration(seconds: seconds);
  }

  void close() => _client.close();
}

class _Robots {
  _Robots(this.rules, this.fetchedAt, {this.unreadable});

  final RobotsRules rules;
  final DateTime fetchedAt;

  /// Why robots.txt could not be read (then nothing is fetched), or null.
  final String? unreadable;
}

class _Cached {
  _Cached({
    required this.bytes,
    required this.checkedAt,
    this.etag,
    this.lastModifiedRaw,
    this.serverMaxAge,
  });

  final List<int> bytes;
  DateTime checkedAt;
  final String? etag;
  final String? lastModifiedRaw;
  final Duration? serverMaxAge;

  /// Our TTL, or the server's `max-age` if that is longer. A server's
  /// `no-store`/`no-cache` does not shorten this: it governs browsers, and our
  /// own minimum interval is what keeps request volume low.
  Duration freshFor(Duration ttl) =>
      (serverMaxAge != null && serverMaxAge! > ttl) ? serverMaxAge! : ttl;

  FetchResult toResult({required bool fromCache}) => FetchResult(
        bytes: bytes,
        fetchedAt: checkedAt,
        fromCache: fromCache,
        etag: etag,
        lastModified:
            lastModifiedRaw == null ? null : _parseHttpDate(lastModifiedRaw!),
      );
}

DateTime? _parseHttpDate(String value) {
  try {
    return DateTime.parse(
      value,
    ); // ISO input only; HTTP dates handled below by http package
  } on FormatException {
    return _httpDate(value);
  }
}

DateTime? _httpDate(String value) {
  // RFC 7231 IMF-fixdate: "Mon, 08 Dec 2025 08:24:06 GMT"
  final m = RegExp(
    r'^\w{3}, (\d{2}) (\w{3}) (\d{4}) (\d{2}):(\d{2}):(\d{2}) GMT$',
  ).firstMatch(value.trim());
  if (m == null) return null;
  const months = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];
  final month = months.indexOf(m.group(2)!) + 1;
  if (month == 0) return null;
  return DateTime.utc(
    int.parse(m.group(3)!),
    month,
    int.parse(m.group(1)!),
    int.parse(m.group(4)!),
    int.parse(m.group(5)!),
    int.parse(m.group(6)!),
  );
}
