import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../../core/clock.dart';
import '../../transport/data/sources/source_status.dart';
import '../../transport/data/transport_repository.dart';
import '../../transport/domain/arrival_status.dart';
import '../../dashboard/domain/demand_overview.dart';
import '../domain/service_filter.dart';
import '../../transport/domain/transport_service.dart';
import '../../transport/domain/transport_type.dart';
import '../../../core/l10n/strings.dart';

enum LoadStatus { loading, ready, error }

/// Holds arrivals, the active filter and refresh state for all screens.
class ArrivalsController extends ChangeNotifier {
  ArrivalsController({
    required this.repository,
    this.clock = systemClock,
    this.staleAfter = const Duration(minutes: 10),
    this.scheduledStaleAfter = const Duration(hours: 36),
    this.slowAfter = const Duration(seconds: 9),
  });

  final TransportRepository repository;

  /// How long the first load may take before the loading view explains that the
  /// server could be waking up.
  final Duration slowAfter;
  final Clock clock;

  /// Live or estimated data older than this is flagged as stale.
  final Duration staleAfter;

  /// Timetable-only data changes rarely (the backend refreshes it every few
  /// hours), so it is flagged as stale only after this much longer time.
  final Duration scheduledStaleAfter;

  LoadStatus _status = LoadStatus.loading;
  TransportSnapshot? _snapshot;
  TransportFetchException? _error;
  ServiceFilter _filter = const ServiceFilter();
  bool _refreshing = false;
  bool _slowLoad = false;
  Timer? _slowTimer;
  bool _disposed = false;

  LoadStatus get status => _status;
  TransportSnapshot? get snapshot => _snapshot;
  ServiceFilter get filter => _filter;
  bool get isRefreshing => _refreshing;

  /// Set when the latest refresh failed. If [snapshot] is non-null the older
  /// data is still shown, flagged as outdated.
  TransportFetchException? get error => _error;

  DateTime get now => clock();

  /// True when the list contains demo data.
  bool get hasMock => allServices.any((s) => s.source.isMock);

  /// True when the list contains data from a real source.
  bool get hasReal => allServices.any((s) => !s.source.isMock);

  /// True when every service shown is demo data.
  bool get isMock => hasMock && !hasReal;

  /// True when any service has an estimated or actual time. Timetable-only
  /// lists have none, and their times must not be read as live.
  bool get hasLiveTimes => allServices.any((s) => !s.isScheduleOnly);

  /// Per-source status from the backend (empty for demo data).
  List<SourceStatusInfo> get sources => _snapshot?.sources ?? const [];

  /// True when the server reported sources but none of them can supply data
  /// (all failed or unusable): an empty list then means "no data", not "no
  /// arrivals".
  bool get noSourceAvailable =>
      sources.isNotEmpty && sources.every((s) => !s.providesData);

  /// True when the first load is still pending after [slowAfter]: the hosted
  /// server may be waking up. Never true once data or an error has arrived.
  bool get isSlowLoad => _slowLoad;

  Duration? get dataAge =>
      _snapshot == null ? null : now.difference(_snapshot!.fetchedAt);

  bool get isStale =>
      dataAge != null &&
      dataAge! > (hasLiveTimes ? staleAfter : scheduledStaleAfter);

  List<TransportService> get allServices => _snapshot?.services ?? const [];

  /// Services still relevant now, soonest first: not yet arrived, and not a
  /// schedule-only/expired entry whose time already passed without confirmation.
  List<TransportService> get upcoming {
    final current = now;
    return (const ServiceFilter().apply(allServices)).where((service) {
      final status = service.statusAt(current);
      if (status == ArrivalStatus.arrived) return false;
      if (status == ArrivalStatus.unknown &&
          service.minutesUntil(current) < 0) {
        return false;
      }
      return true;
    }).toList();
  }

  /// All services matching the active filter, soonest first.
  List<TransportService> get filtered => _filter.apply(allServices);

  DemandOverview get demand => DemandOverview.compute(allServices, now);

  int countFor(TransportType? type) => type == null
      ? allServices.length
      : allServices.where((s) => s.type == type).length;

  void setType(TransportType? type) {
    _filter = type == null
        ? _filter.copyWith(clearType: true)
        : _filter.copyWith(type: type);
    notifyListeners();
  }

  void setQuery(String query) {
    _filter = _filter.copyWith(query: query);
    notifyListeners();
  }

  void clearFilters() {
    _filter = const ServiceFilter();
    notifyListeners();
  }

  /// Starts a refresh unless one is already running (so pull-to-refresh and
  /// the retry button cannot stack requests).
  Future<void> refresh() async {
    if (_refreshing) return;
    _refreshing = true;
    if (_snapshot == null) {
      _status = LoadStatus.loading;
      _slowLoad = false;
      _slowTimer = Timer(slowAfter, () {
        _slowLoad = true;
        _notify();
      });
      _notify();
    }
    try {
      _snapshot = await repository.fetchUpcomingArrivals();
      _status = LoadStatus.ready;
      _error = null;
    } on TransportFetchException catch (e) {
      _error = e;
      if (_snapshot == null) _status = LoadStatus.error;
    } catch (_) {
      _error = const TransportFetchException(Strings.unexpectedError);
      if (_snapshot == null) _status = LoadStatus.error;
    } finally {
      _refreshing = false;
      _slowTimer?.cancel();
      _slowTimer = null;
      _slowLoad = false;
      _notify();
    }
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _slowTimer?.cancel();
    super.dispose();
  }
}
