import 'dart:async';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:suceava_alerts_backend/suceava_alerts_backend.dart';
import 'package:test/test.dart';

const agent = 'SuceavaTravelAlerts/0.1 (+me@example.org)';

class Harness {
  Harness(
    Map<String, http.Response Function(http.Request)> routes, {
    Duration minInterval = const Duration(seconds: 5),
    Duration ttl = const Duration(hours: 6),
  }) {
    client = MockClient((request) async {
      requests.add(request);
      final handler = routes[request.url.path];
      if (handler == null) return http.Response('not found', 404);
      return handler(request);
    });
    fetcher = PoliteFetcher(
      userAgent: agent,
      client: client,
      now: () => clock,
      minInterval: minInterval,
      ttl: ttl,
      sleep: (d) async {
        sleeps.add(d);
        clock = clock.add(d);
      },
    );
  }

  DateTime clock = DateTime.utc(2026, 10, 21, 9);
  final List<http.Request> requests = [];
  final List<Duration> sleeps = [];
  late final MockClient client;
  late final PoliteFetcher fetcher;

  List<String> get paths => [for (final r in requests) r.url.path];
}

http.Response ok(String body, {Map<String, String> headers = const {}}) =>
    http.Response(body, 200, headers: headers);

void main() {
  final page = Uri.parse('https://example.org/orar');

  test('reads robots.txt first, then the page, identifying itself', () async {
    final h = Harness({
      '/robots.txt': (_) => ok('User-agent: *\nDisallow: /private/'),
      '/orar': (_) => ok('hello'),
    });
    final result = await h.fetcher.get(page);
    expect(result.text, 'hello');
    expect(result.fromCache, isFalse);
    expect(h.paths, ['/robots.txt', '/orar']);
    expect(h.requests.every((r) => r.headers['user-agent'] == agent), isTrue);
  });

  test('a path forbidden by robots.txt is never requested', () async {
    final h = Harness({
      '/robots.txt': (_) => ok('User-agent: *\nDisallow: /orar'),
      '/orar': (_) => ok('secret'),
    });
    await expectLater(
      h.fetcher.get(page),
      throwsA(
          isA<FetchException>().having((e) => e.blocked, 'blocked', isTrue)),
    );
    expect(h.paths, ['/robots.txt']);
  });

  test('a missing robots.txt allows access', () async {
    final h = Harness({'/orar': (_) => ok('hello')});
    expect((await h.fetcher.get(page)).text, 'hello');
  });

  test('an unreadable robots.txt (server error) blocks access', () async {
    final h = Harness({
      '/robots.txt': (_) => http.Response('oops', 500),
      '/orar': (_) => ok('hello'),
    });
    await expectLater(h.fetcher.get(page), throwsA(isA<FetchException>()));
    expect(h.paths, ['/robots.txt']);
  });

  test('says whether robots.txt forbids the path or could not be read',
      () async {
    final forbids = Harness({
      '/robots.txt': (_) => ok('User-agent: *\nDisallow: /orar'),
    });
    await expectLater(
      forbids.fetcher.get(page),
      throwsA(isA<FetchException>()
          .having((e) => e.message, 'message', contains('nu permite'))),
    );

    final unreadable = Harness({
      '/robots.txt': (_) => http.Response('blocked', 403),
    });
    await expectLater(
      unreadable.fetcher.get(page),
      throwsA(isA<FetchException>().having(
        (e) => e.message,
        'message',
        allOf(contains('nu a putut fi citit'), contains('HTTP 403')),
      )),
    );
  });

  test('keeps a short description of each answer, without the query', () async {
    final h = Harness({
      '/orar': (_) => ok(
            '<html><head><title>  Just a\n moment...  </title></head></html>',
            headers: {'content-type': 'text/html; charset=utf-8'},
          ),
    });
    await h.fetcher.get(Uri.parse('https://example.org/orar?token=SECRET'));
    final text = h.fetcher.describeResponses();
    expect(text, contains('example.org/orar'));
    expect(text, contains('HTTP 200'));
    expect(text, contains('text/html'));
    expect(text, contains('titlu "Just a moment..."'));
    expect(text, isNot(contains('SECRET')));
    h.fetcher.clearResponseLog();
    expect(h.fetcher.describeResponses(), isEmpty);
  });

  test('describes a bot-check style page by its visible text and server',
      () async {
    final h = Harness({
      '/orar': (_) => ok(
            '<html><head><title>Wait</title><style>p{}</style></head><body>'
            '<script>var x=1;</script><p>Checking your browser before '
            'accessing the site.</p></body></html>',
            headers: {'content-type': 'text/html', 'server': 'LiteSpeed'},
          ),
    });
    await h.fetcher.get(page);
    final text = h.fetcher.describeResponses();
    expect(text, contains('server LiteSpeed'));
    expect(text, contains('text "Checking your browser before accessing'));
    expect(text, isNot(contains('var x')));
    expect(text, isNot(contains('p{}')));
  });

  test(
    'an unreadable robots.txt is a transient failure, re-checked after minutes',
    () async {
      var robotsCalls = 0;
      final h = Harness({
        '/robots.txt': (_) {
          robotsCalls++;
          return robotsCalls == 1
              ? http.Response('busy', 503)
              : ok('User-agent: *\nDisallow:');
        },
        '/orar': (_) => ok('hello'),
      });
      await expectLater(
        h.fetcher.get(page),
        throwsA(
          isA<FetchException>().having((e) => e.blocked, 'blocked', isFalse),
        ),
      );
      // Within ten minutes the answer is reused; the page is still untouched.
      h.clock = h.clock.add(const Duration(minutes: 5));
      await expectLater(h.fetcher.get(page), throwsA(isA<FetchException>()));
      expect(robotsCalls, 1);
      expect(h.paths, ['/robots.txt']);

      h.clock = h.clock.add(const Duration(minutes: 11));
      expect((await h.fetcher.get(page)).text, 'hello');
      expect(robotsCalls, 2);
    },
  );

  test('robots.txt is fetched once per host and reused', () async {
    final h = Harness({
      '/robots.txt': (_) => ok('User-agent: *\nDisallow:'),
      '/a': (_) => ok('a'),
      '/b': (_) => ok('b'),
    });
    await h.fetcher.get(Uri.parse('https://example.org/a'));
    await h.fetcher.get(Uri.parse('https://example.org/b'));
    expect(h.paths.where((p) => p == '/robots.txt'), hasLength(1));
  });

  test('responses are cached for the TTL', () async {
    final h = Harness({'/orar': (_) => ok('hello')});
    await h.fetcher.get(page);
    h.clock = h.clock.add(const Duration(hours: 5));
    final again = await h.fetcher.get(page);
    expect(again.fromCache, isTrue);
    expect(h.paths.where((p) => p == '/orar'), hasLength(1));
  });

  test('after the TTL it revalidates with the ETag; 304 keeps the body',
      () async {
    final h = Harness({
      '/orar': (r) => r.headers['if-none-match'] == '"v1"'
          ? http.Response('', 304)
          : ok('hello', headers: {'etag': '"v1"'}),
    });
    await h.fetcher.get(page);
    h.clock = h.clock.add(const Duration(hours: 7));
    final again = await h.fetcher.get(page);
    expect(again.text, 'hello');
    expect(again.fromCache, isTrue);
    expect(h.requests.last.headers['if-none-match'], '"v1"');
  });

  test('after the TTL a changed page replaces the cached body', () async {
    var version = 1;
    final h = Harness({'/orar': (_) => ok('v$version')});
    await h.fetcher.get(page);
    version = 2;
    h.clock = h.clock.add(const Duration(hours: 7));
    expect((await h.fetcher.get(page)).text, 'v2');
  });

  test("a server's longer max-age extends the cache lifetime", () async {
    final h = Harness({
      '/orar': (_) => ok('hello', headers: {'cache-control': 'max-age=86400'}),
    });
    await h.fetcher.get(page);
    h.clock = h.clock.add(const Duration(hours: 20));
    expect((await h.fetcher.get(page)).fromCache, isTrue);
  });

  test('requests to the same host are spaced by the minimum interval',
      () async {
    final h = Harness({
      '/robots.txt': (_) => ok('User-agent: *\nDisallow:'),
      '/a': (_) => ok('a'),
      '/b': (_) => ok('b'),
    });
    await h.fetcher.get(Uri.parse('https://example.org/a'));
    h.sleeps.clear();
    await h.fetcher.get(Uri.parse('https://example.org/b'));
    expect(h.sleeps, isNotEmpty);
    expect(h.sleeps.first, const Duration(seconds: 5));
  });

  test('a robots Crawl-delay longer than the minimum is honoured', () async {
    final h = Harness({
      '/robots.txt': (_) =>
          ok('User-agent: *\nCrawl-delay: 10\nDisallow: /api/'),
      '/a': (_) => ok('a'),
      '/b': (_) => ok('b'),
    });
    await h.fetcher.get(Uri.parse('https://example.org/a'));
    h.sleeps.clear();
    await h.fetcher.get(Uri.parse('https://example.org/b'));
    expect(h.sleeps.first, const Duration(seconds: 10));
  });

  test('429 with Retry-After blocks further requests until it has passed',
      () async {
    var limited = true;
    final h = Harness({
      '/orar': (_) => limited
          ? http.Response('slow down', 429, headers: {'retry-after': '120'})
          : ok('hello'),
    });
    await expectLater(
      h.fetcher.get(page),
      throwsA(
          isA<FetchException>().having((e) => e.blocked, 'blocked', isTrue)),
    );
    final before = h.requests.length;

    h.clock = h.clock.add(const Duration(seconds: 60));
    await expectLater(h.fetcher.get(page), throwsA(isA<FetchException>()));
    expect(h.requests.length, before, reason: 'no request while backing off');

    limited = false;
    h.clock = h.clock.add(const Duration(seconds: 120));
    expect((await h.fetcher.get(page)).text, 'hello');
  });

  test('403 is treated as a block and is not worked around', () async {
    final h = Harness({'/orar': (_) => http.Response('no', 403)});
    await expectLater(
      h.fetcher.get(page),
      throwsA(
          isA<FetchException>().having((e) => e.blocked, 'blocked', isTrue)),
    );
    expect(h.paths.where((p) => p == '/orar'), hasLength(1));
  });

  test('a server error is a plain failure, not a block', () async {
    final h = Harness({'/orar': (_) => http.Response('boom', 500)});
    await expectLater(
      h.fetcher.get(page),
      throwsA(
          isA<FetchException>().having((e) => e.blocked, 'blocked', isFalse)),
    );
  });

  test('a timeout becomes a safe FetchException', () async {
    final client = MockClient((r) async {
      if (r.url.path == '/robots.txt') return http.Response('', 404);
      await Completer<void>().future; // never completes
      return http.Response('', 200);
    });
    final fetcher = PoliteFetcher(
      userAgent: agent,
      client: client,
      timeout: const Duration(milliseconds: 50),
      minInterval: Duration.zero,
    );
    await expectLater(fetcher.get(page), throwsA(isA<FetchException>()));
  });

  test('a body larger than the limit is refused', () async {
    final client = MockClient.streaming((request, _) async {
      if (request.url.path == '/robots.txt') {
        return http.StreamedResponse(Stream.value([]), 404);
      }
      return http.StreamedResponse(
        Stream.value(List.filled(10, 65)),
        200,
        contentLength: 999999999,
      );
    });
    final fetcher = PoliteFetcher(
      userAgent: agent,
      client: client,
      maxBytes: 1000,
      minInterval: Duration.zero,
    );
    await expectLater(fetcher.get(page), throwsA(isA<FetchException>()));
  });
}
