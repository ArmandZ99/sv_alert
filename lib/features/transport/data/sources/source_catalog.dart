import '../../domain/transport_type.dart';

/// Where a candidate source stands. Nothing is [verified] until it is
/// authorized, implemented and checked against real data.
enum IntegrationStatus {
  /// Authorized, implemented and checked against real data.
  verified,

  /// Implemented in the backend from a public, openly published source and
  /// working on real data, but timetable-only. Not [verified]: for pages
  /// without an explicit reuse licence, permission is still unconfirmed.
  implementedScheduledOnly,

  /// Technically accessible, but an account, key or subscription is needed.
  awaitingCredentials,

  /// Reuse needs written permission or a partnership first.
  awaitingPermission,

  /// Looks usable but origin, coverage or freshness are not confirmed yet.
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
      status: IntegrationStatus.implementedScheduledOnly,
      nature: SourceNature.scheduledOnly,
      notes:
          'Backend reads the weekly arrival tables in the page (one season, with '
          'its stated period) and the linked arrivals PDF for the next season, '
          'each within its own period. No live status, no API; the page says '
          'all rights reserved and publishes no terms, so reuse permission is '
          'unconfirmed. The PDF needs pdftotext on the backend host.',
    ),
    DataSourceInfo(
      id: 'aerodatabox',
      name: 'AeroDataBox (API.Market / RapidAPI)',
      type: TransportType.flight,
      officialUrl: 'https://doc.aerodatabox.com/',
      status: IntegrationStatus.awaitingCredentials,
      nature: SourceNature.unknown,
      notes:
          'Optional live provider, not implemented. Needs an account; SCV '
          'coverage, estimated-time fields and terms must be verified first. '
          'The key must live on the backend, never in the app.',
    ),
    DataSourceInfo(
      id: 'ro-rail-open-timetable',
      name: 'Orar tren - date deschise (data.gov.ro)',
      type: TransportType.train,
      officialUrl:
          'https://data.gov.ro/dataset/mers-tren-sntfc-cfr-calatori-s-a',
      status: IntegrationStatus.implementedScheduledOnly,
      nature: SourceNature.scheduledOnly,
      notes:
          'Official annual timetable (OGL-ROU-1.0), valid 14 Dec 2025 - 12 Dec '
          '2026; covers Suceava, Suceava Nord and Suceava Vest. Static: no '
          'delays. Dataset URLs change every December.',
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
      id: 'tasa-suceava',
      name: 'TASA Suceava - trasee',
      type: TransportType.coach,
      officialUrl: 'https://www.tasasuceava.ro/trasee/',
      status: IntegrationStatus.implementedScheduledOnly,
      nature: SourceNature.scheduledOnly,
      notes:
          'Operator route page, read by the backend (robots.txt allows it). '
          'No validity period or operating days published: assumed daily.',
    ),
    DataSourceInfo(
      id: 'scv-airport-transfer',
      name: 'Transfer Cernăuți - Suceava - Aeroport',
      type: TransportType.coach,
      officialUrl:
          'https://www.aeroportsuceava.ro/ro/info-pasageri/transfer-aeroport',
      status: IntegrationStatus.implementedScheduledOnly,
      nature: SourceNature.scheduledOnly,
      notes:
          'Shuttle timetable on the airport site. No validity end published; '
          'which of the two operators runs each trip is not stated.',
    ),
    DataSourceInfo(
      id: 'tarsin',
      name: 'Tarsin - orar autocare',
      type: TransportType.coach,
      officialUrl: 'https://www.tarsin.ro/ro/routes/radauti-suceava',
      status: IntegrationStatus.unavailable,
      nature: SourceNature.unknown,
      notes:
          'Timetable loads from a JavaScript app; public pages carry none. '
          'Using its internal API is not done. Needs an agreement or feed.',
    ),
    DataSourceInfo(
      id: 'autogari-sosiri',
      name: 'Autogari.ro - Sosiri în Suceava',
      type: TransportType.coach,
      officialUrl: 'https://www.autogari.ro/Suceava/Sosiri',
      status: IntegrationStatus.awaitingPermission,
      nature: SourceNature.scheduledOnly,
      notes:
          'Terms section 8.1 forbids copying content without prior written '
          'consent; no API or licence offered. Not used.',
    ),
  ];

  static List<DataSourceInfo> forType(TransportType type) =>
      all.where((s) => s.type == type).toList();

  /// Whether any source for [type] is verified and may feed real data.
  static bool hasVerifiedSource(TransportType type) =>
      forType(type).any((s) => s.status == IntegrationStatus.verified);

  /// Whether any source for [type] is implemented (timetable-only or better).
  static bool hasImplementedSource(TransportType type) => forType(type).any(
    (s) =>
        s.status == IntegrationStatus.verified ||
        s.status == IntegrationStatus.implementedScheduledOnly,
  );
}
