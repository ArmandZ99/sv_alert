import 'package:flutter/material.dart';

import '../domain/arrival_status.dart';
import '../domain/transport_service.dart';
import '../domain/transport_type.dart';
import '../../../core/l10n/strings.dart';
import '../../../core/theme/app_theme.dart';

extension TransportTypeStyle on TransportType {
  String get label => switch (this) {
    TransportType.flight => Strings.typeFlight,
    TransportType.train => Strings.typeTrain,
    TransportType.coach => Strings.typeCoach,
  };

  String get filterLabel => switch (this) {
    TransportType.flight => Strings.filterFlights,
    TransportType.train => Strings.filterTrains,
    TransportType.coach => Strings.filterCoaches,
  };

  IconData get icon => switch (this) {
    TransportType.flight => Icons.flight_rounded,
    TransportType.train => Icons.train_rounded,
    TransportType.coach => Icons.directions_bus_rounded,
  };

  Color get color => switch (this) {
    TransportType.flight => AppColors.flight,
    TransportType.train => AppColors.train,
    TransportType.coach => AppColors.coach,
  };
}

extension ArrivalStatusStyle on ArrivalStatus {
  String get label => switch (this) {
    ArrivalStatus.onTime => Strings.statusOnTime,
    ArrivalStatus.delayed => Strings.statusDelayed,
    ArrivalStatus.arrivingSoon => Strings.statusArrivingSoon,
    ArrivalStatus.arrived => Strings.statusArrived,
    ArrivalStatus.cancelled => Strings.statusCancelled,
    ArrivalStatus.unknown => Strings.statusUnknown,
  };

  IconData get icon => switch (this) {
    ArrivalStatus.onTime => Icons.check_circle_outline,
    ArrivalStatus.delayed => Icons.schedule,
    ArrivalStatus.arrivingSoon => Icons.notifications_active_outlined,
    ArrivalStatus.arrived => Icons.task_alt,
    ArrivalStatus.cancelled => Icons.cancel_outlined,
    ArrivalStatus.unknown => Icons.help_outline,
  };

  Color get color => switch (this) {
    ArrivalStatus.onTime => AppColors.ok,
    ArrivalStatus.delayed => AppColors.warning,
    ArrivalStatus.arrivingSoon => AppColors.primary,
    ArrivalStatus.arrived => AppColors.neutral,
    ArrivalStatus.cancelled => AppColors.danger,
    ArrivalStatus.unknown => AppColors.neutral,
  };
}

extension DataQualityLabel on DataQuality {
  String get label => switch (this) {
    DataQuality.scheduled => Strings.dataScheduled,
    DataQuality.estimated => Strings.dataEstimated,
    DataQuality.live => Strings.dataLive,
    DataQuality.unknown => Strings.dataUnknown,
  };
}

/// Status text including the delay; sample delays are explicitly labelled.
String describeStatus(TransportService service, ArrivalStatus status) {
  if (status != ArrivalStatus.delayed) return status.label;
  final delay = service.delayMinutes ?? 0;
  final base = '${status.label} +${Strings.minutesShort(delay)}';
  return service.source.isMock ? '$base · ${Strings.sampleSuffix}' : base;
}
