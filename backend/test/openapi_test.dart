import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shelf/shelf.dart';
import 'package:suceava_alerts_backend/suceava_alerts_backend.dart';
import 'package:test/test.dart';
import 'package:yaml/yaml.dart';

/// The OpenAPI file is documentation people will trust, so it is checked
/// against what the backend really returns: real handler output, the golden
/// file the app also parses, and the spec's own examples are validated against
/// the schemas, and its enums are kept in step with the Dart enums.
typedef Json = Map<String, dynamic>;

final Json spec = load();

Json load() {
  final text = File('openapi.yaml').readAsStringSync();
  return jsonDecode(jsonEncode(loadYaml(text))) as Json;
}

Json resolve(Json schema) {
  final ref = schema[r'$ref'] as String?;
  if (ref == null) return schema;
  var node = spec as dynamic;
  for (final part in ref.substring(2).split('/')) {
    node = node[part];
  }
  return resolve(node as Json);
}

final _offset = RegExp(r'(Z|[+-]\d{2}:\d{2})$');

/// A small validator for the subset of OpenAPI 3.0 schema this file uses.
List<String> validate(Json schemaIn, Object? value, [String path = r'$']) {
  final schema = resolve(schemaIn);
  if (value == null) {
    return schema['nullable'] == true ? [] : ['$path: null is not allowed'];
  }
  final errors = <String>[];
  final enumValues = schema['enum'] as List?;
  if (enumValues != null && !enumValues.contains(value)) {
    errors.add('$path: "$value" is not one of $enumValues');
  }
  switch (schema['type']) {
    case 'string':
      if (value is! String) {
        return ['$path: expected string, got ${value.runtimeType}'];
      }
      if (schema['format'] == 'date-time') {
        if (DateTime.tryParse(value) == null || !_offset.hasMatch(value)) {
          errors.add('$path: "$value" is not a date-time with an offset');
        }
      }
      if (schema['format'] == 'date') {
        if (!RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(value) ||
            DateTime.tryParse(value) == null) {
          errors.add('$path: "$value" is not a date');
        }
      }
    case 'integer':
      if (value is! int) {
        return ['$path: expected integer, got ${value.runtimeType}'];
      }
      final min = schema['minimum'];
      if (min != null && value < (min as num)) {
        errors.add('$path: $value is below $min');
      }
    case 'boolean':
      if (value is! bool) {
        return ['$path: expected boolean, got ${value.runtimeType}'];
      }
    case 'array':
      if (value is! List) {
        return ['$path: expected array, got ${value.runtimeType}'];
      }
      final min = schema['minItems'];
      if (min != null && value.length < (min as int)) {
        errors.add('$path: fewer than $min items');
      }
      final items = schema['items'] as Json?;
      if (items != null) {
        for (var i = 0; i < value.length; i++) {
          errors.addAll(validate(items, value[i], '$path[$i]'));
        }
      }
    case 'object':
      if (value is! Map) {
        return ['$path: expected object, got ${value.runtimeType}'];
      }
      final properties = (schema['properties'] as Json?) ?? {};
      for (final key in (schema['required'] as List?) ?? const []) {
        if (!value.containsKey(key)) {
          errors.add('$path: missing required "$key"');
        }
      }
      if (schema['additionalProperties'] == false) {
        for (final key in value.keys) {
          if (!properties.containsKey(key)) {
            errors.add('$path: undocumented field "$key"');
          }
        }
      }
      for (final entry in properties.entries) {
        if (value.containsKey(entry.key)) {
          errors.addAll(validate(
              entry.value as Json, value[entry.key], '$path.${entry.key}'));
        }
      }
  }
  return errors;
}

Json schemaOf(String path, String status) {
  final responses =
      ((spec['paths'] as Json)[path] as Json)['get']['responses'] as Json;
  final content = (responses[status] as Json);
  final resolved = resolve(content);
  return resolved['content']['application/json']['schema'] as Json;
}

/// A tiny fixed timetable, so the real handler can be exercised without a network.
class _Adapter extends SourceAdapter {
  @override
  SourceDescriptor get descriptor => const SourceDescriptor(
        id: 'fake',
        name: 'Fake source',
        kind: TransportKind.train,
        url: 'https://example.org/fake',
      );

  @override
  Future<AdapterLoad> load(PoliteFetcher fetcher, DateTime now) async =>
      AdapterLoad(
        connection: SourceConnection.scheduledOnly,
        message: 'Orar programat.',
        fetchedAt: now,
        validFrom: DateTime.utc(2026, 1, 1),
        validTo: DateTime.utc(2026, 12, 31),
        patterns: [
          SchedulePattern(
            serviceNumber: 'IR 1',
            operatorName: null,
            routeStops: const ['A', 'Suceava'],
            arrivalPoint: 'Gara Suceava',
            arrivalMinutes: 12 * 60,
            calendar: [everyDay()],
          ),
        ],
      );
}

void main() {
  final now = DateTime.utc(2026, 10, 21, 9);
  late Handler handler;

  setUp(() {
    final pipeline = TransportPipeline(
      adapters: [
        _Adapter(),
        UnusedSources.autogari(),
        UnusedSources.aeroDataBox(hasKey: false)
      ],
      fetcher: PoliteFetcher(
        userAgent: 'test',
        client: MockClient((_) async => http.Response('', 500)),
        now: () => now,
      ),
      now: () => now,
    );
    handler = buildHandler(pipeline, now: () => now);
  });

  Future<(int, Json, Map<String, String>)> call(String path,
      {String method = 'GET'}) async {
    final response =
        await handler(Request(method, Uri.parse('http://localhost/$path')));
    return (
      response.statusCode,
      jsonDecode(await response.readAsString()) as Json,
      response.headers,
    );
  }

  group('structure', () {
    test('documents exactly the three real endpoints, GET only', () {
      final paths = spec['paths'] as Json;
      expect(paths.keys.toSet(), {'/healthz', '/v1/sources', '/v1/arrivals'});
      for (final entry in paths.entries) {
        expect((entry.value as Json).keys.toList(), ['get'], reason: entry.key);
      }
    });

    test('operation ids are unique and the window parameters are documented',
        () {
      final paths = spec['paths'] as Json;
      final ids = [
        for (final p in paths.values) (p as Json)['get']['operationId']
      ];
      expect(ids.toSet().length, ids.length);
      for (final path in ['/v1/arrivals', '/v1/sources']) {
        final params = [
          for (final p in ((paths[path] as Json)['get']['parameters'] as List))
            resolve(p as Json)['name'],
        ];
        expect(params, ['from', 'to'], reason: path);
      }
      expect(((paths['/healthz'] as Json)['get']['parameters']), isNull);
    });

    test('documented status codes are the ones the backend returns', () {
      final paths = spec['paths'] as Json;
      expect((((paths['/healthz'] as Json)['get'])['responses'] as Json).keys,
          ['200', '405']);
      for (final path in ['/v1/arrivals', '/v1/sources']) {
        expect((((paths[path] as Json)['get'])['responses'] as Json).keys,
            ['200', '400', '405']);
      }
    });

    test('enums match the Dart enums, so they cannot drift apart', () {
      final schemas = (spec['components'] as Json)['schemas'] as Json;
      expect(schemas['TransportKind']['enum'],
          [for (final v in TransportKind.values) v.name]);
      expect(schemas['DataQuality']['enum'],
          [for (final v in DataQuality.values) v.name]);
      expect(schemas['SourceConnection']['enum'],
          [for (final v in SourceConnection.values) v.name]);
    });

    test('no delay or live-estimate fields are invented', () {
      final service =
          ((spec['components'] as Json)['schemas'] as Json)['Service'] as Json;
      final keys = (service['properties'] as Json).keys.toSet();
      expect(keys.any((k) => k.toLowerCase().contains('delay')), isFalse);
      expect(
          keys.containsAll(
              {'estimatedArrival', 'actualArrival', 'isCancelled'}),
          isTrue);
      final text = File('openapi.yaml').readAsStringSync();
      expect(text, contains('**no live data**'));
      expect(text, contains('Always `null` today'));
    });

    test('the Service schema documents every field the backend serializes',
        () async {
      final (_, body, _) = await call(
          'v1/arrivals?from=2026-10-21T00:00:00Z&to=2026-10-22T00:00:00Z');
      final real = ((body['services'] as List).first as Json).keys.toSet();
      final service =
          ((spec['components'] as Json)['schemas'] as Json)['Service'] as Json;
      expect((service['properties'] as Json).keys.toSet(), real);
      expect((service['required'] as List).toSet(), real);
    });
  });

  group('real responses validate against the schemas', () {
    test('/healthz', () async {
      final (status, body, _) = await call('healthz');
      expect(status, 200);
      expect(validate(schemaOf('/healthz', '200'), body), isEmpty);
    });

    test('/v1/arrivals with a window', () async {
      final (status, body, headers) = await call(
        'v1/arrivals?from=2026-10-21T00:00:00Z&to=2026-10-22T00:00:00Z',
      );
      expect(status, 200);
      expect(validate(schemaOf('/v1/arrivals', '200'), body), isEmpty);
      expect(headers['cache-control'], 'public, max-age=60');
      expect(headers['content-type'], startsWith('application/json'));
      expect((body['services'] as List), isNotEmpty);
    });

    test('/v1/arrivals with no parameters uses the documented default window',
        () async {
      final (status, body, _) = await call('v1/arrivals');
      expect(status, 200);
      expect(validate(schemaOf('/v1/arrivals', '200'), body), isEmpty);
      expect(body['window']['from'],
          '2026-10-21T08:30:00.000Z'); // 30 minutes before
      expect(
          body['window']['to'], '2026-10-22T09:00:00.000Z'); // 24 hours after
    });

    test('/v1/arrivals accepts an offset, with the plus sign encoded',
        () async {
      final (status, body, _) = await call(
        'v1/arrivals?from=2026-10-21T12:00:00%2B03:00&to=2026-10-22T12:00:00%2B03:00',
      );
      expect(status, 200);
      expect(body['window']['from'], '2026-10-21T09:00:00.000Z');
    });

    test('/v1/sources', () async {
      final (status, body, _) = await call('v1/sources');
      expect(status, 200);
      expect(validate(schemaOf('/v1/sources', '200'), body), isEmpty);
      expect(body.keys, ['sources']);
    });

    test('the golden file the app also parses', () {
      final golden = jsonDecode(
          File('../test/fixtures/backend_output_v1.json').readAsStringSync());
      expect(validate(schemaOf('/v1/arrivals', '200'), golden), isEmpty);
    });

    test('every source status the backend can report is documented', () async {
      final (_, body, _) = await call('v1/sources');
      final statuses = {
        for (final s in body['sources'] as List) (s as Json)['status']
      };
      expect(statuses,
          containsAll(['scheduledOnly', 'unavailable', 'awaitingCredentials']));
      expect(
          statuses.difference({
            'connected',
            'scheduledOnly',
            'unavailable',
            'awaitingCredentials'
          }),
          isEmpty);
    });
  });

  group('error responses match their documentation', () {
    test('bad windows give 400 with the documented bodies', () async {
      final badFormat = await call('v1/arrivals?from=yesterday');
      expect(badFormat.$1, 400);
      expect(validate(schemaOf('/v1/arrivals', '400'), badFormat.$2), isEmpty);
      final examples =
          (resolve({r'$ref': '#/components/responses/BadWindow'})['content']
              ['application/json']['examples']) as Json;
      expect(badFormat.$2['error'], examples['badFormat']['value']['error']);

      final noOffset = await call(
          'v1/arrivals?from=2026-10-21T10:00:00&to=2026-10-21T12:00:00');
      expect(noOffset.$1, 400);

      final reversed = await call(
          'v1/sources?from=2026-10-22T00:00:00Z&to=2026-10-21T00:00:00Z');
      expect(reversed.$1, 400);

      final tooLong = await call(
          'v1/arrivals?from=2026-10-01T00:00:00Z&to=2026-10-21T00:00:00Z');
      expect(tooLong.$1, 400);
      expect(tooLong.$2['error'], examples['tooLong']['value']['error']);
    });

    test('a non-GET method gives 405 with the documented body', () async {
      for (final path in ['healthz', 'v1/arrivals', 'v1/sources']) {
        final (status, body, _) = await call(path, method: 'POST');
        expect(status, 405, reason: path);
        expect(validate(schemaOf('/v1/arrivals', '405'), body), isEmpty);
        expect(body['error'], 'method not allowed');
      }
    });

    test('an unknown path answers 404 with the same error shape', () async {
      final (status, body, _) = await call('nope');
      expect(status, 404);
      expect(validate(resolve({r'$ref': '#/components/schemas/Error'}), body),
          isEmpty);
    });
  });

  group('the spec\'s own examples are valid', () {
    test('every response example validates against its schema', () {
      var checked = 0;
      void check(Json content, String where) {
        final media = content['application/json'] as Json?;
        if (media == null) return;
        final schema = media['schema'] as Json;
        final values = [
          if (media.containsKey('example')) media['example'],
          if (media['examples'] != null)
            for (final e in (media['examples'] as Json).values)
              (e as Json)['value'],
        ];
        for (final v in values) {
          expect(validate(schema, v), isEmpty, reason: where);
          checked++;
        }
      }

      final paths = spec['paths'] as Json;
      for (final entry in paths.entries) {
        final responses =
            ((entry.value as Json)['get'] as Json)['responses'] as Json;
        for (final r in responses.entries) {
          check(resolve(r.value as Json)['content'] as Json,
              '${entry.key} ${r.key}');
        }
      }
      for (final r
          in ((spec['components'] as Json)['responses'] as Json).entries) {
        check((r.value as Json)['content'] as Json, 'responses/${r.key}');
      }
      expect(checked, greaterThanOrEqualTo(6));
    });
  });

  group('the validator itself', () {
    final service =
        ((spec['components'] as Json)['schemas'] as Json)['Service'] as Json;
    late Json good;
    setUp(() async {
      final (_, body, _) = await call(
          'v1/arrivals?from=2026-10-21T00:00:00Z&to=2026-10-22T00:00:00Z');
      good = ((body['services'] as List).first as Json);
    });

    test('accepts a real service',
        () => expect(validate(service, good), isEmpty));

    test('rejects an invented field', () {
      expect(validate(service, {...good, 'delayMinutes': 12}), isNotEmpty);
    });

    test('rejects a missing field, a wrong enum value and a naive timestamp',
        () {
      expect(validate(service, {...good}..remove('lastUpdated')), isNotEmpty);
      expect(
          validate(service, {...good, 'dataQuality': 'live-ish'}), isNotEmpty);
      expect(
          validate(
              service, {...good, 'scheduledArrival': '2026-10-21T12:00:00'}),
          isNotEmpty);
    });
  });
}
