import 'package:travelalerts/core/time/bucharest_time.dart';
import 'package:travelalerts/features/transport/data/transport_repository.dart';
import 'package:travelalerts/features/transport/domain/arrival_status.dart';
import 'package:travelalerts/features/transport/domain/transport_service.dart';
import 'package:travelalerts/features/transport/domain/transport_type.dart';

/// 12:00 in Bucharest (EEST, UTC+3) on 2026-10-21.
final DateTime testNow = DateTime.utc(2026, 10, 21, 9, 0);

DateTime minutesFrom(int minutes) => testNow.add(Duration(minutes: minutes));

/// Builds a service whose times are minute offsets from [base] (default
/// [testNow]), which is also when it was last updated.
TransportService makeService({
  String id = 's1',
  TransportType type = TransportType.train,
  String number = 'IR 1831',
  String? operatorName = 'Operator X',
  List<String> stops = const ['Iași', 'Pașcani', 'Suceava'],
  String arrivalPoint = 'Gara Suceava',
  int scheduled = 30,
  int? estimated,
  int? actual,
  bool cancelled = false,
  bool mock = false,
  DataQuality quality = DataQuality.estimated,
  DateTime? base,
}) {
  final origin = base ?? testNow;
  DateTime at(int minutes) => origin.add(Duration(minutes: minutes));
  return TransportService(
    id: id,
    type: type,
    source: SourceInfo(name: 'test', isMock: mock),
    serviceNumber: number,
    operatorName: operatorName,
    routeStops: stops,
    arrivalPoint: arrivalPoint,
    serviceDate: BucharestTime.serviceDateOf(origin),
    scheduledArrival: at(scheduled),
    estimatedArrival: estimated == null ? null : at(estimated),
    actualArrival: actual == null ? null : at(actual),
    isCancelled: cancelled,
    dataQuality: quality,
    lastUpdated: origin,
  );
}

class FakeRepository implements TransportRepository {
  FakeRepository(this.responses);

  /// Each call consumes one entry: a snapshot or an exception to throw.
  final List<Object> responses;
  int calls = 0;

  @override
  Future<TransportSnapshot> fetchUpcomingArrivals() async {
    final next =
        responses[calls < responses.length ? calls : responses.length - 1];
    calls++;
    if (next is TransportSnapshot) return next;
    throw next;
  }
}
