import '../../domain/transport_type.dart';

/// Where a candidate source stands. Nothing is [verified] until an adapter
/// exists, is authorized and has been checked against real responses.
enum IntegrationStatus {
  /// Authorized, implemented and checked against real data.
  verified,

  /// Technically accessible, but an account, key or subscription is needed.
  awaitingCredentials,

  /// Reuse needs written permission or a partnership first.
  awaitingPermission,

  /// Looks usable (for example an open licence) but origin, coverage or
  /// freshness have not been confirmed yet.
  awaitingVerification,

  /// No usable access method found.
  unavailable,
}

/// What kind of times a source can provide, as far as it is confirmed.
enum SourceNature {
  /// Timetable only: never a live estimate.
  scheduledOnly,

  /// Claims live or estimated times (field-level behaviour still to verify).
  liveEstimated,

  /// Not established.
  unknown,
}

class DataSourceInfo {
  const DataSourceInfo({
    required this.id,
    required this.name,
    required this.type,
    required this.officialUrl,
    required this.status,
    required this.nature,
    required this.notes,
  });

  final String id;
  final String name;
  final TransportType type;
  final String officialUrl;
  final IntegrationStatus status;
  final SourceNature nature;

  /// Developer-facing summary. Full detail: docs/DATA_SOURCE_FEASIBILITY.md.
  final String notes;
}

/// Candidate sources and their honest status. Update this together with
/// docs/DATA_SOURCE_FEASIBILITY.md whenever access is confirmed or refused.
abstract final class DataSourceCatalog {
  static const List<DataSourceInfo> all = [
    DataSourceInfo(
      id: 'scv-airport-timetable',
      name: 'Aeroportul Suceava - orar publicat',
      type: TransportType.flight,
      officialUrl: 'https://aeroportsuceava.ro/ro/2016-01-29-10-35-08',
      status: IntegrationStatus.awaitingPermission,
      nature: SourceNature.scheduledOnly,
      notes:
          'Seasonal timetable as web tables and PDFs. No live status, no API or '
          'feed, no terms of use found; footer says all rights reserved.',
    ),
    DataSourceInfo(
      id: 'aerodatabox',
      name: 'AeroDataBox (API.Market / RapidAPI)',
      type: TransportType.flight,
      officialUrl: 'https://doc.aerodatabox.com/',
      status: IntegrationStatus.awaitingCredentials,
      nature: SourceNature.unknown,
      notes:
          'Commercial API with airport arrivals (FIDS). Pricing and licence '
          'terms confirmed; field-level docs and SCV coverage not verified. '
          'Key must live on a backend, never in the app.',
    ),
    DataSourceInfo(
      id: 'cfr-trenul-meu',
      name: 'CFR Călători / Infofer - Trenul meu',
      type: TransportType.train,
      officialUrl: 'https://bilete.cfrcalatori.ro/ro-RO/Trains',
      status: IntegrationStatus.awaitingPermission,
      nature: SourceNature.liveEstimated,
      notes:
          'Public website shows real-time progress and delay per train. No '
          'documented API; terms are silent on automated access, which is not '
          'permission. Needs written agreement.',
    ),
    DataSourceInfo(
      id: 'ro-railway-gtfs',
      name: 'Orar tren - date deschise Informatică Feroviară (GTFS)',
      type: TransportType.train,
      officialUrl: 'https://mobilitydatabase.org/feeds/gtfs/mdb-3236',
      status: IntegrationStatus.awaitingVerification,
      nature: SourceNature.scheduledOnly,
      notes:
          'Open licence (OGL-ROU-1.0) timetable, but only seen through a '
          'third-party conversion. Origin, Suceava coverage and download '
          'authorization not yet verified. Timetable only, no delays.',
    ),
    DataSourceInfo(
      id: 'autogari-sosiri',
      name: 'Autogari.ro - Sosiri în Suceava',
      type: TransportType.coach,
      officialUrl: 'https://www.autogari.ro/Suceava/Sosiri',
      status: IntegrationStatus.awaitingPermission,
      nature: SourceNature.scheduledOnly,
      notes:
          'Timetable-style listing. Terms section 8.1 forbids copying content '
          'without prior written consent; no API or licence offered.',
    ),
    DataSourceInfo(
      id: 'coach-operator-feeds',
      name: 'Feeduri directe ale operatorilor de autocare',
      type: TransportType.coach,
      officialUrl: 'https://www.autogari.ro/CompaniiTransport',
      status: IntegrationStatus.unavailable,
      nature: SourceNature.unknown,
      notes:
          'No operator feed or API found. Would need individual agreements '
          'with each operator serving Suceava.',
    ),
  ];

  static List<DataSourceInfo> forType(TransportType type) =>
      all.where((s) => s.type == type).toList();

  /// Whether any source for [type] is verified and may feed real data.
  static bool hasVerifiedSource(TransportType type) =>
      forType(type).any((s) => s.status == IntegrationStatus.verified);
}
