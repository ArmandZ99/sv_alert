import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:travelalerts/features/transport/data/sources/normalized_arrivals_parser.dart';
import 'package:travelalerts/features/transport/data/sources/provider_config.dart';
import 'package:travelalerts/features/transport/data/sources/source_catalog.dart';
import 'package:travelalerts/features/transport/data/transport_repository.dart';
import 'package:travelalerts/features/transport/domain/arrival_status.dart';
import 'package:travelalerts/features/transport/domain/transport_type.dart';

Object? fixture() => jsonDecode(
  File('test/fixtures/normalized_arrivals_v1.json').readAsStringSync(),
);

void main() {
  group('NormalizedArrivalsParser', () {
    late ParsedArrivals parsed;
    setUp(() => parsed = NormalizedArrivalsParser.parse(fixture()));

    test('accepts the three valid services, one per transport type', () {
      expect(
        parsed.snapshot.services.map((s) => s.type).toSet(),
        TransportType.values.toSet(),
      );
      expect(parsed.snapshot.services, hasLength(3));
      expect(parsed.snapshot.fetchedAt, DateTime.utc(2026, 10, 21, 9));
      expect(parsed.snapshot.isMock, isFalse);
    });

    test(
      'rejects invalid services and says why, instead of dropping them silently',
      () {
        expect(parsed.rejected, hasLength(4));
        expect(
          parsed.rejected.join('\n'),
          allOf(
            contains('explicit UTC offset'),
            contains('estimated/actual time given'),
            contains('origin and destination'),
            contains('unknown transport type'),
          ),
        );
      },
    );

    test('offsets are normalized to UTC instants', () {
      final flight = parsed.snapshot.services.firstWhere(
        (s) => s.type == TransportType.flight,
      );
      expect(
        flight.scheduledArrival,
        DateTime.utc(2026, 10, 21, 17, 10),
      ); // 20:10 +03:00
      expect(flight.estimatedArrival, DateTime.utc(2026, 10, 21, 17, 40));
      expect(flight.scheduledArrival.isUtc, isTrue);
      expect(flight.delayMinutes, 30);
    });

    test('live train keeps estimate, delay, source time and quality', () {
      final train = parsed.snapshot.services.firstWhere(
        (s) => s.type == TransportType.train,
      );
      expect(train.dataQuality, DataQuality.live);
      expect(train.delayMinutes, 20);
      expect(train.sourceTimestamp, DateTime.utc(2026, 10, 21, 8, 58, 30));
      expect(train.source.url, 'https://example.invalid/source');
      expect(train.serviceDate, DateTime.utc(2026, 10, 21));
    });

    test('a scheduled coach has no estimate and never looks live', () {
      final coach = parsed.snapshot.services.firstWhere(
        (s) => s.type == TransportType.coach,
      );
      expect(coach.isScheduleOnly, isTrue);
      expect(coach.estimatedArrival, isNull);
      expect(coach.delayMinutes, isNull);
      expect(
        coach.statusAt(DateTime.utc(2026, 10, 21, 9)),
        ArrivalStatus.scheduled,
      );
    });

    test('mock flag follows the payload', () {
      final json = fixture() as Map;
      for (final s in json['services'] as List) {
        (s['source'] as Map)['isMock'] = true;
      }
      expect(NormalizedArrivalsParser.parse(json).snapshot.isMock, isTrue);
    });

    test('unusable payloads raise a safe TransportFetchException', () {
      expect(
        () => NormalizedArrivalsParser.parse('nope'),
        throwsA(isA<TransportFetchException>()),
      );
      expect(
        () => NormalizedArrivalsParser.parse({'schemaVersion': 2}),
        throwsA(isA<TransportFetchException>()),
      );
      expect(
        () => NormalizedArrivalsParser.parse({
          'schemaVersion': 1,
          'services': [],
        }),
        throwsA(isA<TransportFetchException>()), // missing fetchedAt
      );
      expect(
        () => NormalizedArrivalsParser.parse({
          'schemaVersion': 1,
          'fetchedAt': '2026-10-21T09:00:00',
          'services': [],
        }),
        throwsA(isA<TransportFetchException>()), // naive fetchedAt
      );
    });

    test('impossible service dates are rejected', () {
      final json = fixture() as Map;
      ((json['services'] as List).first as Map)['serviceDate'] = '2026-02-30';
      final result = NormalizedArrivalsParser.parse(json);
      expect(result.snapshot.services, hasLength(2));
    });

    test('an empty list of services is valid and not flagged mock', () {
      final result = NormalizedArrivalsParser.parse({
        'schemaVersion': 1,
        'fetchedAt': '2026-10-21T09:00:00Z',
        'services': [],
      });
      expect(result.snapshot.services, isEmpty);
      expect(result.snapshot.isMock, isFalse);
    });
  });

  group('ProviderConfig.validate', () {
    test('no value means mock-only and is valid', () {
      for (final empty in [null, '', '   ']) {
        final result = ProviderConfig.validate(empty);
        expect(result.isValid, isTrue);
        expect(result.config.hasBackend, isFalse);
      }
    });

    test('accepts an https backend URL', () {
      final result = ProviderConfig.validate('https://api.example.ro/v1');
      expect(result.isValid, isTrue);
      expect(result.config.apiBaseUrl, Uri.parse('https://api.example.ro/v1'));
    });

    test('allows plain http only for local development hosts', () {
      expect(ProviderConfig.validate('http://10.0.2.2:8080').isValid, isTrue);
      expect(ProviderConfig.validate('http://localhost:8080').isValid, isTrue);
      expect(ProviderConfig.validate('http://api.example.ro').isValid, isFalse);
    });

    test('rejects credentials, query strings and fragments in the URL', () {
      for (final bad in [
        'https://user:pass@api.example.ro',
        'https://api.example.ro?key=SECRET123',
        'https://api.example.ro/#frag',
      ]) {
        final result = ProviderConfig.validate(bad);
        expect(result.isValid, isFalse, reason: bad);
        expect(result.config.hasBackend, isFalse, reason: bad);
      }
    });

    test('rejects garbage and never echoes the value in its errors', () {
      final result = ProviderConfig.validate('sk_live_SECRET123');
      expect(result.isValid, isFalse);
      expect(result.errors.join(), isNot(contains('SECRET123')));
      final withKey = ProviderConfig.validate(
        'https://api.example.ro?apikey=SECRET123',
      );
      expect(withKey.errors.join(), isNot(contains('SECRET123')));
    });

    test('without an override the central default backend is used', () {
      final config = ProviderConfig.fromEnvironment().config;
      expect(config.hasBackend, isTrue);
      expect(
        config.apiBaseUrl.toString(),
        'https://suceava-travel-alerts-api.onrender.com',
      );
    });
  });

  group('DataSourceCatalog', () {
    test('covers all three transport types, coaches included', () {
      for (final type in TransportType.values) {
        expect(DataSourceCatalog.forType(type), isNotEmpty, reason: '$type');
      }
    });

    test('no source is claimed verified: nothing real is integrated yet', () {
      expect(
        DataSourceCatalog.all.where(
          (s) => s.status == IntegrationStatus.verified,
        ),
        isEmpty,
      );
      for (final type in TransportType.values) {
        expect(DataSourceCatalog.hasVerifiedSource(type), isFalse);
      }
    });

    test(
      'every transport type has at least one implemented source, none verified',
      () {
        for (final type in TransportType.values) {
          expect(
            DataSourceCatalog.hasImplementedSource(type),
            isTrue,
            reason: '$type',
          );
        }
      },
    );

    test('sources that are not used are never described as implemented', () {
      for (final id in [
        'tarsin',
        'autogari-sosiri',
        'aerodatabox',
        'cfr-trenul-meu',
      ]) {
        final source = DataSourceCatalog.all.firstWhere((s) => s.id == id);
        expect(
          source.status,
          isNot(IntegrationStatus.implementedScheduledOnly),
          reason: id,
        );
        expect(source.status, isNot(IntegrationStatus.verified), reason: id);
      }
    });

    test('ids are unique and every source has an https link and notes', () {
      expect(
        DataSourceCatalog.all.map((s) => s.id).toSet(),
        hasLength(DataSourceCatalog.all.length),
      );
      for (final s in DataSourceCatalog.all) {
        expect(s.officialUrl, startsWith('https://'));
        expect(s.notes, isNotEmpty);
      }
    });

    test('timetable-only sources are never described as live', () {
      final scheduled = DataSourceCatalog.all.where(
        (s) => s.nature == SourceNature.scheduledOnly,
      );
      expect(scheduled, isNotEmpty);
      for (final s in scheduled) {
        expect(s.notes.toLowerCase(), isNot(contains('live status provided')));
      }
    });
  });
}
