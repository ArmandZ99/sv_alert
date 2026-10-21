import 'package:flutter/foundation.dart';

import '../../../core/clock.dart';
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
  });

  final TransportRepository repository;
  final Clock clock;

  /// Data older than this is flagged as stale.
  final Duration staleAfter;

  LoadStatus _status = LoadStatus.loading;
  TransportSnapshot? _snapshot;
  TransportFetchException? _error;
  ServiceFilter _filter = const ServiceFilter();
  bool _refreshing = false;
  bool _disposed = false;

  LoadStatus get status => _status;
  TransportSnapshot? get snapshot => _snapshot;
  ServiceFilter get filter => _filter;
  bool get isRefreshing => _refreshing;

  /// Set when the latest refresh failed. If [snapshot] is non-null the older
  /// data is still shown, flagged as outdated.
  TransportFetchException? get error => _error;

  DateTime get now => clock();

  bool get isMock => _snapshot?.isMock ?? false;

  Duration? get dataAge =>
      _snapshot == null ? null : now.difference(_snapshot!.fetchedAt);

  bool get isStale => dataAge != null && dataAge! > staleAfter;

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

  Future<void> refresh() async {
    if (_refreshing) return;
    _refreshing = true;
    if (_snapshot == null) {
      _status = LoadStatus.loading;
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
      _notify();
    }
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
