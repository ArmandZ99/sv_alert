/// User-facing Romanian strings, kept in one place so an English set (or a
/// move to `gen_l10n`) can replace them later without touching widgets.
abstract final class Strings {
  static const appName = 'Suceava Pulse';
  static const appTagline = 'Sosiri de avion, tren și autocar în Suceava';

  static const navDashboard = 'Panou';
  static const navArrivals = 'Sosiri';
  static const navSettings = 'Setări';

  // Mock / trust labelling
  static const mockBadge = 'DATE DEMO';
  static const mockBannerTitle = 'Date demonstrative (mock)';
  static const mockBannerBody =
      'Cursele, orele și întârzierile sunt exemple generate local. Nu provin '
      'din surse în timp real și nu reflectă situația reală din Suceava.';
  static const mixedBannerTitle = 'Date reale și demonstrative';
  static const mixedBannerBody =
      'Unele curse sunt reale, altele sunt exemple generate local. Cele '
      'demonstrative sunt marcate DATE DEMO.';
  static const scheduledBannerTitle = 'Orar programat, nu timp real';
  static const scheduledBannerBody =
      'Orele sunt cele din orarele publicate de operatori. Întârzierile, '
      'anulările și estimările nu sunt disponibile; o cursă poate sosi mai '
      'devreme sau mai târziu.';
  static const sampleSuffix = 'exemplu';
  static const independentNotice =
      'Aplicație comunitară independentă. Nu este dezvoltată, susținută sau '
      'operată de Bolt, CFR Călători, aeroport sau operatori de transport.';

  // Dashboard
  static const nextArrivals = 'Sosiri următoare';
  static const seeAll = 'Vezi toate';
  static const settingsTooltip = 'Setări notificări';
  static const refreshTooltip = 'Actualizează';

  // Demand
  static const demandTitle = 'POTENȚIAL DE CERERE';
  static const demandSampleBadge = 'EXEMPLU';
  static const demandDisclaimer =
      'Estimare orientativă a activității potențiale, calculată din sosirile din listă. '
      'Nu reprezintă comenzi Bolt reale și nu garantează cerere sau pasageri.';
  static const demandLow = 'Activitate redusă în următoarea oră';
  static const demandModerate = 'Activitate moderată în următoarea oră';
  static const demandHigh = 'Activitate ridicată în următoarea oră';
  static const hubRailway = 'Gară';
  static const hubAirport = 'Aeroport';
  static const hubCoach = 'Autogară';
  static const noArrivalsSoon = 'nicio sosire';

  // Arrivals page
  static const arrivalsTitle = 'Sosiri în Suceava';
  static const arrivalsSubtitle =
      'Avioane, trenuri și autocare, în ordinea sosirii';
  static const searchHint = 'Caută număr, operator sau localitate';
  static const clearSearch = 'Șterge căutarea';
  static const filterAll = 'Toate';
  static const filterFlights = 'Avioane';
  static const filterTrains = 'Trenuri';
  static const filterCoaches = 'Autocare';

  // Transport types
  static const typeFlight = 'AVION';
  static const typeTrain = 'TREN';
  static const typeCoach = 'AUTOCAR';
  static const settingsFlights = 'Avioane';
  static const settingsTrains = 'Trenuri';
  static const settingsCoaches = 'Autocare și autobuze';

  // Times
  static const scheduledLabel = 'Programat';
  static const estimatedLabel = 'Estimat';
  static const arrivedAtLabel = 'Sosit la';
  static const estimateUnavailable = 'Estimare indisponibilă';
  static const noValue = '—';

  // Status
  static const statusScheduled = 'Programat';
  static const statusOnTime = 'La timp';
  static const statusDelayed = 'Întârziat';
  static const statusArrivingSoon = 'Sosește curând';
  static const statusArrived = 'Sosit';
  static const statusCancelled = 'Anulat';
  static const statusUnknown = 'Stare necunoscută';

  // Data quality
  static const dataScheduled = 'Doar orar programat';
  static const dataEstimated = 'Estimare';
  static const dataLive = 'Date live';
  static const dataUnknown = 'Calitate necunoscută';

  // States
  static const loading = 'Se conectează la server și se încarcă sosirile...';
  static const loadingSlow =
      'Serverul poate fi în repaus după o perioadă de inactivitate. Îl '
      'repornim acum. Prima conectare poate dura aproximativ un minut. Te '
      'rugăm să aștepți.';
  static const loadingSlowNote =
      'Poți lăsa aplicația deschisă cât timp se face conectarea.';
  static const errorTitle = 'Nu am putut încărca sosirile';
  static const offlineTitle = 'Fără conexiune la internet';
  static const unexpectedError =
      'A apărut o eroare neașteptată. Încearcă din nou.';
  static const retry = 'Reîncearcă';
  static const emptyTitle = 'Nicio sosire în perioada următoare';
  static const emptyBody = 'Trage în jos pentru a actualiza lista.';
  static const noSourcesTitle = 'Sursele de date nu sunt disponibile acum';
  static const noSourcesBody =
      'Serverul funcționează, dar nu a putut citi niciun orar. Lista goală nu '
      'înseamnă că nu sosește nimic. Detalii găsești în Setări, la Surse de '
      'date.';
  static const noResultsTitle = 'Nicio cursă nu corespunde filtrelor';
  static const clearFilters = 'Șterge filtrele';
  static const staleTitle = 'Datele par vechi';

  // Details
  static const detailsArrivalPoint = 'Punct de sosire';
  static const detailsServiceDate = 'Data cursei';
  static const detailsDelay = 'Întârziere';
  static const detailsRoute = 'Traseu';
  static const detailsDataType = 'Tip de date';
  static const detailsSource = 'Sursă';
  static const detailsSourceLink = 'Link sursă';
  static const detailsNoLink = 'Indisponibil';
  static const detailsLastUpdated = 'Ultima actualizare';
  static const detailsSourceTime = 'Ora raportată de sursă';
  static const detailsUnavailable = 'Indisponibil';
  static const detailsDelayHistory = 'Istoric întârzieri';
  static const detailsDelayHistoryNone =
      'Indisponibil în datele demonstrative.';
  static const followService = 'Urmărește această cursă';
  static const followServiceHint =
      'Preferință salvată doar în aplicație; nu trimite notificări încă.';
  static const close = 'Închide';

  // Settings
  static const settingsTitle = 'Setări';
  static const settingsSubtitle = 'Alege ce notificări vrei să primești.';
  static const notificationsNotActiveTitle =
      'Notificările push nu sunt active încă';
  static const notificationsNotActiveBody =
      'Preferințele sunt salvate pe acest telefon, dar nu declanșează încă '
      'alerte. Alertele reale vor necesita date de transport verificate și un '
      'serviciu de fundal, și vor fi activate separat.';
  static const sectionNotifications = 'Notificări';
  static const notificationsEnabled = 'Notificări active';
  static const notificationsEnabledHint =
      'Comutator general pentru toate alertele';
  static const arrivalAlerts = 'Alerte înainte de sosire';
  static const arrivalAlertsHint = 'Memento când o cursă urmărită se apropie';
  static const delayAlerts = 'Alerte de întârziere';
  static const delayAlertsHint = 'Când întârzierea atinge pragul ales';
  static const sectionTypes = 'Tipuri de transport urmărite';
  static const sectionReminders = 'Memento înainte de sosire';
  static const remindersHint = 'Alege unul sau mai multe momente.';
  static const sectionDelay = 'Întârziere semnificativă';
  static const sectionQuiet = 'Ore liniștite';
  static const quietEnabled = 'Fără notificări în intervalul ales';
  static const quietFrom = 'De la';
  static const quietTo = 'Până la';
  static const sectionFollowed = 'Curse urmărite';
  static const followedNone =
      'Nicio cursă aleasă. Se urmăresc toate cursele din tipurile selectate.';
  static const sectionDataSources = 'Surse de date';
  static const dataSourcesIntro =
      'Momentan toate datele afișate sunt demonstrative. Nicio sursă reală nu '
      'este conectată; mai jos este starea surselor analizate.';
  static const dataSourcesLiveIntro =
      'Stare raportată de serverul de date. Orarele sunt programate, nu în '
      'timp real, cu excepția surselor marcate „Conectat”.';
  static const sourceConnected = 'Conectat (timp real)';
  static const sourceScheduledOnlyLive = 'Doar orar programat';
  static const sourceImplementedScheduled = 'Implementată în server, doar orar';
  static const sourceVerified = 'Verificată';
  static const sourceAwaitingCredentials = 'Necesită cont sau cheie API';
  static const sourceAwaitingPermission = 'Necesită permisiune scrisă';
  static const sourceAwaitingVerification = 'De verificat';
  static const sourceUnavailable = 'Indisponibilă';
  static const sourceScheduledOnly = 'doar orar';
  static const sourceLiveClaimed = 'ar putea oferi estimări live (neverificat)';
  static const sourceNatureUnknown = 'conținut neclar';
  static const sectionAbout = 'Despre';
  static const aboutPrivacy =
      'Versiunea curentă nu creează conturi și nu trimite date personale. '
      'Preferințele de notificare sunt salvate doar pe acest telefon. Nu '
      'folosește locația.';

  static String minutesShort(int minutes) => '$minutes min';
  static String reminderChip(int minutes) => '$minutes min';
  static String delayThresholdLabel(int minutes) =>
      'Alertă când întârzierea ajunge la $minutes minute';
  static String followedCount(int count) =>
      count == 1 ? '1 cursă urmărită' : '$count curse urmărite';
  static String arrivalsNextHour(int count) => count == 1
      ? '1 sosire în următoarea oră'
      : '$count sosiri în următoarea oră';
  static String arrivalsInWindow(int count) =>
      'Din care $count în următoarele 2 ore în total';
  static String scheduleOnlyNote(int count) => count == 1
      ? '1 sosire are doar orar programat, fără estimare.'
      : '$count sosiri au doar orar programat, fără estimare.';
  static String hubArrivals(int count) => count == 0
      ? noArrivalsSoon
      : (count == 1 ? '1 sosire/oră' : '$count sosiri/oră');
}
