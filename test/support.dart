import 'package:travelalerts/data/transport_repository.dart';
import 'package:travelalerts/domain/arrival_status.dart';
import 'package:travelalerts/domain/transport_service.dart';
import 'package:travelalerts/domain/transport_type.dart';

final DateTime testNow = DateTime(2026, 10, 21, 12, 0);

DateTime minutesFrom(int minutes) => testNow.add(Duration(minutes: minutes));

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
}) {
  return TransportService(
    id: id,
    type: type,
    source: SourceInfo(name: 'test', isMock: mock),
    serviceNumber: number,
    operatorName: operatorName,
    routeStops: stops,
    arrivalPoint: arrivalPoint,
    serviceDate: DateTime(testNow.year, testNow.month, testNow.day),
    scheduledArrival: minutesFrom(scheduled),
    estimatedArrival: estimated == null ? null : minutesFrom(estimated),
    actualArrival: actual == null ? null : minutesFrom(actual),
    isCancelled: cancelled,
    dataQuality: quality,
    lastUpdated: testNow,
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
