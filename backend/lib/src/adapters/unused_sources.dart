import '../model/model.dart';
import 'source_adapter.dart';

/// Sources that were evaluated and are deliberately not used. They stay in the
/// status report so the app can show where each one stands.
abstract final class UnusedSources {
  /// Tarsin publishes its timetable only through a JavaScript application:
  /// the HTML route pages carry no schedule. Reading it would mean calling its
  /// internal, undocumented API, which is not a published page and is not
  /// done.
  static SourceAdapter tarsin() => UnusedSourceAdapter(
        descriptor: const SourceDescriptor(
          id: 'tarsin',
          name: 'Tarsin - orar autocare',
          kind: TransportKind.coach,
          url: 'https://www.tarsin.ro/ro/routes/radauti-suceava',
        ),
        reason:
            'Orarul se încarcă dintr-o aplicație JavaScript; paginile publice nu '
            'conțin orarul și nu se folosesc API-uri interne nedocumentate. '
            'Necesită acord sau un feed de la operator.',
      );

  /// Autogari.ro's terms (section 8.1) forbid copying its content without
  /// prior written consent.
  static SourceAdapter autogari() => UnusedSourceAdapter(
        descriptor: const SourceDescriptor(
          id: 'autogari-sosiri',
          name: 'Autogari.ro - Sosiri în Suceava',
          kind: TransportKind.coach,
          url: 'https://www.autogari.ro/Suceava/Sosiri',
        ),
        reason:
            'Termenii site-ului interzic copierea conținutului fără acord scris '
            'prealabil (§8.1); nu este folosit.',
      );

  /// Optional live flight provider. Only the backend may hold its key.
  static SourceAdapter aeroDataBox({required bool hasKey}) =>
      UnusedSourceAdapter(
        descriptor: const SourceDescriptor(
          id: 'aerodatabox',
          name: 'AeroDataBox - zboruri live',
          kind: TransportKind.flight,
          url: 'https://doc.aerodatabox.com/',
        ),
        connection: hasKey
            ? SourceConnection.unavailable
            : SourceConnection.awaitingCredentials,
        reason: hasKey
            ? 'Cheia există, dar adaptorul nu este implementat: acoperirea SCV, '
                'câmpurile de oră estimată și termenii de utilizare trebuie '
                'verificate mai întâi.'
            : 'Necesită un cont și o cheie API (variabila AERODATABOX_API_KEY pe '
                'server). Nu este implementat până la verificarea acoperirii SCV.',
      );
}
