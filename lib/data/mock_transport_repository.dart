import '../core/clock.dart';
import '../domain/arrival_status.dart';
import '../domain/transport_service.dart';
import '../domain/transport_type.dart';
import 'transport_repository.dart';

/// Generated demonstration data. Nothing here comes from a real source: service
/// numbers, routes, operators and delays are invented examples, with times
/// placed relative to "now" so the dashboard always has something to show.
class MockTransportRepository implements TransportRepository {
  MockTransportRepository({
    this.clock = systemClock,
    this.latency = const Duration(milliseconds: 700),
  });

  static const SourceInfo source = SourceInfo(
    name: 'Date demonstrative (mock) — nu sunt date reale',
    isMock: true,
  );

  final Clock clock;
  final Duration latency;

  @override
  Future<TransportSnapshot> fetchUpcomingArrivals() async {
    if (latency > Duration.zero) await Future<void>.delayed(latency);
    final now = clock();
    return TransportSnapshot(
      services: buildServices(now),
      fetchedAt: now,
      isMock: true,
    );
  }

  /// Exposed for tests. Offsets are minutes from [now].
  static List<TransportService> buildServices(DateTime now) {
    final base = DateTime(now.year, now.month, now.day, now.hour, now.minute);
    DateTime at(int minutes) => base.add(Duration(minutes: minutes));
    final serviceDate = DateTime(now.year, now.month, now.day);

    TransportService make({
      required String id,
      required TransportType type,
      required String number,
      String? operatorName,
      required List<String> stops,
      required String arrivalPoint,
      required int scheduled,
      int? estimated,
      int? actual,
      bool cancelled = false,
      required DataQuality quality,
    }) => TransportService(
      id: '$id-${serviceDate.year}${serviceDate.month}${serviceDate.day}',
      type: type,
      source: source,
      serviceNumber: number,
      operatorName: operatorName,
      routeStops: stops,
      arrivalPoint: arrivalPoint,
      serviceDate: serviceDate,
      scheduledArrival: at(scheduled),
      estimatedArrival: estimated == null ? null : at(estimated),
      actualArrival: actual == null ? null : at(actual),
      isCancelled: cancelled,
      dataQuality: quality,
      lastUpdated: now,
    );

    return [
      make(
        id: 'mock-flight-ro212',
        type: TransportType.flight,
        number: 'RO 212',
        operatorName: 'Operator demo',
        stops: ['București Otopeni (OTP)', 'Suceava (SCV)'],
        arrivalPoint: 'Aeroportul Suceava (SCV)',
        scheduled: -20,
        actual: -18,
        quality: DataQuality.estimated,
      ),
      make(
        id: 'mock-coach-radauti',
        type: TransportType.coach,
        number: 'Linia Rădăuți – Suceava',
        operatorName: 'Operator demo C',
        stops: ['Rădăuți', 'Milișăuți', 'Suceava'],
        arrivalPoint: 'Autogara Suceava (punct de confirmat)',
        scheduled: -4,
        quality: DataQuality.scheduled,
      ),
      make(
        id: 'mock-train-ir1831',
        type: TransportType.train,
        number: 'IR 1831',
        operatorName: 'Operator demo',
        stops: [
          'București Nord',
          'Buzău',
          'Adjud',
          'Bacău',
          'Pașcani',
          'Suceava',
        ],
        arrivalPoint: 'Gara Suceava',
        scheduled: 14,
        estimated: 14,
        quality: DataQuality.estimated,
      ),
      make(
        id: 'mock-flight-w41234',
        type: TransportType.flight,
        number: 'W4 1234',
        operatorName: 'Operator demo',
        stops: ['Londra Luton (LTN)', 'Suceava (SCV)'],
        arrivalPoint: 'Aeroportul Suceava (SCV)',
        scheduled: 25,
        estimated: 65,
        quality: DataQuality.estimated,
      ),
      make(
        id: 'mock-train-r5608',
        type: TransportType.train,
        number: 'R 5608',
        operatorName: 'Operator demo',
        stops: [
          'Vatra Dornei',
          'Câmpulung Moldovenesc',
          'Gura Humorului',
          'Suceava',
        ],
        arrivalPoint: 'Gara Suceava',
        scheduled: 30,
        cancelled: true,
        quality: DataQuality.estimated,
      ),
      make(
        id: 'mock-coach-botosani',
        type: TransportType.coach,
        number: 'Linia Botoșani – Suceava',
        operatorName: 'Operator demo A',
        stops: ['Botoșani', 'Dorohoi', 'Suceava'],
        arrivalPoint: 'Autogara Suceava (punct de confirmat)',
        scheduled: 38,
        quality: DataQuality.scheduled,
      ),
      make(
        id: 'mock-train-r5602',
        type: TransportType.train,
        number: 'R 5602',
        operatorName: 'Operator demo',
        stops: ['Pașcani', 'Dolhasca', 'Suceava'],
        arrivalPoint: 'Gara Suceava',
        scheduled: 52,
        estimated: 57,
        quality: DataQuality.estimated,
      ),
      make(
        id: 'mock-coach-iasi',
        type: TransportType.coach,
        number: 'Linia Iași – Suceava',
        operatorName: 'Operator demo B',
        stops: ['Iași', 'Târgu Frumos', 'Pașcani', 'Suceava'],
        arrivalPoint: 'Autogara Suceava (punct de confirmat)',
        scheduled: 70,
        quality: DataQuality.scheduled,
      ),
      make(
        id: 'mock-flight-ro214',
        type: TransportType.flight,
        number: 'RO 214',
        operatorName: 'Operator demo',
        stops: ['București Otopeni (OTP)', 'Suceava (SCV)'],
        arrivalPoint: 'Aeroportul Suceava (SCV)',
        scheduled: 95,
        estimated: 95,
        quality: DataQuality.estimated,
      ),
      make(
        id: 'mock-train-ir1741',
        type: TransportType.train,
        number: 'IR 1741',
        operatorName: 'Operator demo',
        stops: ['București Nord', 'Brașov', 'Adjud', 'Suceava', 'Suceava Nord'],
        arrivalPoint: 'Gara Suceava Nord',
        scheduled: 110,
        estimated: 135,
        quality: DataQuality.estimated,
      ),
    ];
  }
}
