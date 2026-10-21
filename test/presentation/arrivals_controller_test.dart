import 'package:flutter_test/flutter_test.dart';
import 'package:travelalerts/features/transport/data/transport_repository.dart';
import 'package:travelalerts/features/transport/domain/transport_type.dart';
import 'package:travelalerts/features/arrivals/presentation/arrivals_controller.dart';

import '../support.dart';

TransportSnapshot snapshotOf(List<dynamic> services, {DateTime? at}) =>
    TransportSnapshot(
      services: List.of(services.cast()),
      fetchedAt: at ?? testNow,
      isMock: true,
    );

void main() {
  var current = testNow;
  setUp(() => current = testNow);

  ArrivalsController build(FakeRepository repo) =>
      ArrivalsController(repository: repo, clock: () => current);

  test('starts loading, then ready after a successful refresh', () async {
    final controller = build(
      FakeRepository([
        snapshotOf([makeService(scheduled: 20, estimated: 20)]),
      ]),
    );
    expect(controller.status, LoadStatus.loading);
    await controller.refresh();
    expect(controller.status, LoadStatus.ready);
    expect(controller.allServices, hasLength(1));
    expect(controller.error, isNull);
    expect(controller.isMock, isTrue);
  });

  test('first failure gives an error state with the safe message', () async {
    final controller = build(
      FakeRepository([
        const TransportFetchException('Fără rețea', isOffline: true),
      ]),
    );
    await controller.refresh();
    expect(controller.status, LoadStatus.error);
    expect(controller.snapshot, isNull);
    expect(controller.error!.isOffline, isTrue);
  });

  test('unexpected exceptions are mapped to a generic message', () async {
    final controller = build(FakeRepository([StateError('secret internals')]));
    await controller.refresh();
    expect(controller.status, LoadStatus.error);
    expect(controller.error!.message, isNot(contains('secret')));
  });

  test(
    'a failed refresh keeps the previous data and records the error',
    () async {
      final controller = build(
        FakeRepository([
          snapshotOf([makeService(scheduled: 20, estimated: 20)]),
          const TransportFetchException('Serviciu indisponibil'),
        ]),
      );
      await controller.refresh();
      await controller.refresh();
      expect(controller.status, LoadStatus.ready);
      expect(controller.allServices, hasLength(1));
      expect(controller.error, isNotNull);
    },
  );

  test('a later success clears the error', () async {
    final controller = build(
      FakeRepository([
        const TransportFetchException('x'),
        snapshotOf([makeService(scheduled: 20, estimated: 20)]),
      ]),
    );
    await controller.refresh();
    await controller.refresh();
    expect(controller.status, LoadStatus.ready);
    expect(controller.error, isNull);
  });

  test('data becomes stale after the threshold', () async {
    final controller = build(
      FakeRepository([
        snapshotOf([makeService()]),
      ]),
    );
    await controller.refresh();
    current = testNow.add(const Duration(minutes: 10));
    expect(controller.isStale, isFalse);
    current = testNow.add(const Duration(minutes: 11));
    expect(controller.isStale, isTrue);
    expect(controller.dataAge, const Duration(minutes: 11));
  });

  test(
    'upcoming drops arrived and expired entries, sorted soonest first',
    () async {
      final controller = build(
        FakeRepository([
          snapshotOf([
            makeService(id: 'late', scheduled: 50, estimated: 50),
            makeService(id: 'arrived', scheduled: -10, actual: -9),
            makeService(id: 'expired', scheduled: -5),
            makeService(id: 'soon', scheduled: 10, estimated: 10),
            makeService(id: 'cancelled', scheduled: 20, cancelled: true),
          ]),
        ]),
      );
      await controller.refresh();
      expect(controller.upcoming.map((s) => s.id), [
        'soon',
        'cancelled',
        'late',
      ]);
    },
  );

  test('filters by type and query and reports counts', () async {
    final controller = build(
      FakeRepository([
        snapshotOf([
          makeService(id: 't', number: 'IR 1831', scheduled: 20, estimated: 20),
          makeService(
            id: 'f',
            type: TransportType.flight,
            number: 'W4 1234',
            scheduled: 30,
            estimated: 30,
          ),
        ]),
      ]),
    );
    await controller.refresh();
    controller.setType(TransportType.flight);
    expect(controller.filtered.map((s) => s.id), ['f']);
    controller.setQuery('ir');
    expect(controller.filtered, isEmpty);
    controller.clearFilters();
    expect(controller.filtered, hasLength(2));
    expect(controller.countFor(TransportType.train), 1);
    expect(controller.countFor(null), 2);
  });

  test('concurrent refreshes only hit the repository once', () async {
    final repo = FakeRepository([
      snapshotOf([makeService()]),
    ]);
    final controller = build(repo);
    await Future.wait([controller.refresh(), controller.refresh()]);
    expect(repo.calls, 1);
  });
}
