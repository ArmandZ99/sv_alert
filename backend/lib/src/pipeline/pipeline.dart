import '../adapters/source_adapter.dart';
import '../fetch/polite_fetcher.dart';
import '../model/model.dart';

class PipelineSnapshot {
  const PipelineSnapshot({
    required this.generatedAt,
    required this.dataFetchedAt,
    required this.from,
    required this.to,
    required this.services,
    required this.sources,
  });

  final DateTime generatedAt;

  /// Age of the oldest data used: when its source was last fetched.
  final DateTime dataFetchedAt;
  final DateTime from;
  final DateTime to;
  final List<NormalizedService> services;
  final List<SourceStatus> sources;

  Map<String, Object?> toJson() => {
        'schemaVersion': 1,
        'fetchedAt': dataFetchedAt.toUtc().toIso8601String(),
        'generatedAt': generatedAt.toUtc().toIso8601String(),
        'window': {
          'from': from.toUtc().toIso8601String(),
          'to': to.toUtc().toIso8601String(),
        },
        'services': [for (final s in services) s.toJson()],
        'sources': [for (final s in sources) s.toJson()],
      };
}

/// Loads every adapter, keeps the last good data of each, and expands the
/// patterns into dated services for a time window.
///
/// One failing source never affects the others: its error becomes its status.
/// If a source fails after having loaded before, its previous timetable is
/// kept (timetables change rarely) and the status says that the refresh
/// failed.
class TransportPipeline {
  TransportPipeline({
    required this.adapters,
    required this.fetcher,
    Now? now,
    this.refreshEvery = const Duration(hours: 6),
    this.retryAfterFailure = const Duration(minutes: 30),
    this.retryAfterBlock = const Duration(hours: 6),
  }) : _now = now ?? DateTime.now;

  final List<SourceAdapter> adapters;
  final PoliteFetcher fetcher;
  final Duration refreshEvery;
  final Duration retryAfterFailure;
  final Duration retryAfterBlock;
  final Now _now;

  final Map<String, _State> _states = {};
  Future<void>? _inflight;

  _State _state(SourceAdapter a) =>
      _states.putIfAbsent(a.descriptor.id, _State.new);

  /// Refreshes the sources that are due. Concurrent calls share one run.
  Future<void> ensureFresh() =>
      _inflight ??= _run().whenComplete(() => _inflight = null);

  Future<void> _run() async {
    // One source at a time: sources on the same host must not be hit in
    // parallel, and total volume stays small.
    for (final adapter in adapters) {
      final state = _state(adapter);
      final due = state.nextAttempt;
      if (due != null && _now().isBefore(due)) continue;
      await _load(adapter, state);
    }
  }

  Future<void> _load(SourceAdapter adapter, _State state) async {
    final now = _now();
    fetcher.clearResponseLog();
    try {
      final load = await adapter.load(fetcher, now);
      state.load = load;
      state.error = null;
      state.nextAttempt = now.add(refreshEvery);
    } on FetchException catch (e) {
      state.error = e.message;
      state.nextAttempt =
          now.add(e.blocked ? retryAfterBlock : retryAfterFailure);
    } on FormatException catch (e) {
      // Say what was received: a changed layout and an error or bot-check page
      // served to this server look the same to the parser, not to a person.
      final received = fetcher.describeResponses();
      state.error =
          'Conținutul sursei nu a putut fi interpretat (${e.message}). Date '
          'ignorate.${received.isEmpty ? '' : ' Primit: $received.'}';
      state.nextAttempt = now.add(retryAfterFailure);
      // A structure we no longer understand is not trusted, even if an older
      // parse exists.
      state.load = null;
    } catch (_) {
      state.error = 'Eroare neașteptată la citirea sursei.';
      state.nextAttempt = now.add(retryAfterFailure);
    }
  }

  PipelineSnapshot arrivals({required DateTime from, required DateTime to}) {
    final now = _now();
    final services = <NormalizedService>[];
    final sources = <SourceStatus>[];
    DateTime? oldest;

    for (final adapter in adapters) {
      final d = adapter.descriptor;
      final state = _state(adapter);
      final load = state.load;

      if (load == null) {
        sources.add(
          SourceStatus(
            id: d.id,
            name: d.name,
            types: adapter.kinds,
            url: d.url,
            connection: SourceConnection.unavailable,
            message: state.error ?? 'Sursa nu a fost încă încărcată.',
          ),
        );
        continue;
      }

      var connection = load.connection;
      var message = load.message;
      if (state.error != null && load.patterns.isNotEmpty) {
        message = 'Ultima reîmprospătare a eșuat (${state.error}); se folosesc '
            'datele preluate la ${load.fetchedAt?.toUtc().toIso8601String()}. '
            '$message';
        connection = SourceConnection.scheduledOnly;
      } else if (state.error != null) {
        connection = SourceConnection.unavailable;
        message = state.error!;
      }

      final produced = load.patterns.isEmpty || load.fetchedAt == null
          ? const <NormalizedService>[]
          : expandPatterns(
              source: d,
              patterns: load.patterns,
              from: from,
              to: to,
              fetchedAt: load.fetchedAt!,
              sourceTimestamp: load.sourceTimestamp,
            );
      services.addAll(produced);
      if (produced.isNotEmpty || load.patterns.isNotEmpty) {
        final f = load.fetchedAt;
        if (f != null && (oldest == null || f.isBefore(oldest))) oldest = f;
      }
      sources.add(
        SourceStatus(
          id: d.id,
          name: d.name,
          types: adapter.kinds,
          url: d.url,
          connection: connection,
          message: message,
          fetchedAt: load.fetchedAt,
          validFrom: load.validFrom,
          validTo: load.validTo,
          serviceCount: produced.length,
        ),
      );
    }

    services.sort((a, b) {
      final c = a.scheduledArrival.compareTo(b.scheduledArrival);
      return c != 0 ? c : a.id.compareTo(b.id);
    });
    return PipelineSnapshot(
      generatedAt: now,
      dataFetchedAt: oldest ?? now,
      from: from,
      to: to,
      services: services,
      sources: sources,
    );
  }
}

class _State {
  AdapterLoad? load;
  String? error;
  DateTime? nextAttempt;
}
