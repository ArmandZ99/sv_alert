import 'package:flutter_test/flutter_test.dart';
import 'package:travelalerts/data/mock_transport_repository.dart';
import 'package:travelalerts/domain/arrival_status.dart';
import 'package:travelalerts/domain/transport_type.dart';

import '../support.dart';

void main() {
  late MockTransportRepository repository;

  setUp(() {
    repository = MockTransportRepository(
      clock: () => testNow,
      latency: Duration.zero,
    );
  });

  test('snapshot is flagged as mock and stamped with the clock', () async {
    final snapshot = await repository.fetchUpcomingArrivals();
    expect(snapshot.isMock, isTrue);
    expect(snapshot.fetchedAt, testNow);
  });

  test('every service is explicitly marked as mock data', () async {
    final snapshot = await repository.fetchUpcomingArrivals();
    expect(snapshot.services, isNotEmpty);
    for (final service in snapshot.services) {
      expect(service.source.isMock, isTrue, reason: service.id);
      expect(service.source.name, contains('mock'));
      expect(service.source.url, isNull);
    }
  });

  test('covers flights, trains and coaches with full routes', () async {
    final services = (await repository.fetchUpcomingArrivals()).services;
    expect(services.map((s) => s.type).toSet(), TransportType.values.toSet());
    for (final service in services) {
      expect(
        service.routeStops.length,
        greaterThanOrEqualTo(2),
        reason: service.id,
      );
      expect(service.arrivalPoint, isNotEmpty);
      expect(service.serviceNumber, isNotEmpty);
    }
  });

  test('ids are unique', () async {
    final services = (await repository.fetchUpcomingArrivals()).services;
    expect(services.map((s) => s.id).toSet().length, services.length);
  });

  test(
    'sample data exercises scheduled-only, delayed, cancelled and arrived',
    () async {
      final services = (await repository.fetchUpcomingArrivals()).services;
      final statuses = services.map((s) => s.statusAt(testNow)).toSet();
      expect(
        statuses,
        containsAll([
          ArrivalStatus.delayed,
          ArrivalStatus.cancelled,
          ArrivalStatus.arrived,
          ArrivalStatus.arrivingSoon,
          ArrivalStatus.unknown,
        ]),
      );
      expect(
        services.any((s) => s.isScheduleOnly && s.type == TransportType.coach),
        isTrue,
      );
    },
  );
}
