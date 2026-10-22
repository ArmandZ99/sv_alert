import 'package:flutter_test/flutter_test.dart';
import 'package:travelalerts/features/arrivals/domain/service_filter.dart';
import 'package:travelalerts/features/transport/domain/transport_type.dart';

import '../support.dart';

void main() {
  final train = makeService(
    id: 't',
    number: 'IR 1831',
    scheduled: 40,
    stops: ['București Nord', 'Suceava'],
  );
  final flight = makeService(
    id: 'f',
    type: TransportType.flight,
    number: 'W4 1234',
    operatorName: 'Wizz',
    scheduled: 10,
    stops: ['Londra Luton (LTN)', 'Suceava (SCV)'],
    arrivalPoint: 'Aeroportul Suceava',
  );
  final coach = makeService(
    id: 'c',
    type: TransportType.coach,
    number: 'Linia Botoșani – Suceava',
    operatorName: 'Operator A',
    scheduled: 25,
    estimated: 30,
    stops: ['Botoșani', 'Suceava'],
    arrivalPoint: 'Autogara',
  );
  final all = [train, flight, coach];

  test('empty filter keeps everything sorted by effective arrival', () {
    final result = const ServiceFilter().apply(all);
    expect(result.map((s) => s.id), ['f', 'c', 't']);
  });

  test('filters by type', () {
    expect(
      const ServiceFilter(
        type: TransportType.train,
      ).apply(all).map((s) => s.id),
      ['t'],
    );
  });

  test('search ignores case, spaces and diacritics', () {
    expect(const ServiceFilter(query: 'ir1831').apply(all).map((s) => s.id), [
      't',
    ]);
    expect(const ServiceFilter(query: 'BOTOSANI').apply(all).map((s) => s.id), [
      'c',
    ]);
    expect(
      const ServiceFilter(query: 'bucuresti').apply(all).map((s) => s.id),
      ['t'],
    );
  });

  test('search covers operator and origin', () {
    expect(const ServiceFilter(query: 'wizz').apply(all).map((s) => s.id), [
      'f',
    ]);
    expect(const ServiceFilter(query: 'luton').apply(all).map((s) => s.id), [
      'f',
    ]);
  });

  test('type and query combine; no match gives an empty list', () {
    expect(
      const ServiceFilter(type: TransportType.coach, query: 'wizz').apply(all),
      isEmpty,
    );
  });

  test('isActive reflects filter state', () {
    expect(const ServiceFilter().isActive, isFalse);
    expect(const ServiceFilter(query: ' ').isActive, isFalse);
    expect(const ServiceFilter(type: TransportType.train).isActive, isTrue);
  });
}
