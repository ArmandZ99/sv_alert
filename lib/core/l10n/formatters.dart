import '../time/bucharest_time.dart';

String _two(int value) => value.toString().padLeft(2, '0');

/// Wall-clock time of an instant in Europe/Bucharest.
String formatTime(DateTime instant) {
  final local = BucharestTime.of(instant);
  return '${_two(local.hour)}:${_two(local.minute)}';
}

/// A calendar date (such as a service date): only year, month and day are read.
String formatDate(DateTime date) =>
    '${_two(date.day)}.${_two(date.month)}.${date.year}';

/// Date and wall-clock time of an instant in Europe/Bucharest.
String formatDateTime(DateTime instant) {
  final local = BucharestTime.of(instant);
  return '${formatDate(local)} ${formatTime(instant)}';
}

String formatMinuteOfDay(int minutes) =>
    '${_two(minutes ~/ 60)}:${_two(minutes % 60)}';

/// "în 14 min", "în 1 h 25 min", "acum 3 min" (past).
String formatUntil(int minutes) {
  if (minutes == 0) return 'acum';
  final abs = minutes.abs();
  final text = abs >= 60
      ? (abs % 60 == 0 ? '${abs ~/ 60} h' : '${abs ~/ 60} h ${abs % 60} min')
      : '$abs min';
  return minutes > 0 ? 'în $text' : 'acum $text';
}

/// "Actualizat chiar acum", "Actualizat acum 2 min", "Actualizat acum 1 h 5 min".
String formatUpdatedAgo(Duration age) {
  final minutes = age.inMinutes;
  if (minutes < 1) return 'Actualizat chiar acum';
  return 'Actualizat acum ${_span(minutes)}';
}

String formatAge(Duration age) {
  final minutes = age.inMinutes;
  return minutes < 1 ? 'chiar acum' : 'acum ${_span(minutes)}';
}

String _span(int minutes) {
  if (minutes < 60) return '$minutes min';
  final rest = minutes % 60;
  return rest == 0 ? '${minutes ~/ 60} h' : '${minutes ~/ 60} h $rest min';
}
