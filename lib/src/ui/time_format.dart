/// Wall-clock / date formatting without pulling in `intl`.
///
/// These read the public [DateTime] getters, so they work for both native
/// `DateTime` and `TZDateTime` values from package:timezone.
library;

String two(int value) => value.toString().padLeft(2, '0');

/// `14:05` / `2:05 pm` style clock text.
String formatWallClock(
  DateTime moment, {
  bool use24Hour = true,
  bool withSeconds = true,
  bool lowercaseAmPm = false,
}) {
  if (use24Hour) {
    final base = '${two(moment.hour)}:${two(moment.minute)}';
    return withSeconds ? '$base:${two(moment.second)}' : base;
  }
  final hour24 = moment.hour % 12;
  final displayHour = hour24 == 0 ? 12 : hour24;
  final suffix = moment.hour < 12 ? 'AM' : 'PM';
  final spaced = lowercaseAmPm ? suffix.toLowerCase() : suffix;
  final base = '$displayHour:${two(moment.minute)}';
  final clock = withSeconds ? '$base:${two(moment.second)}' : base;
  return lowercaseAmPm ? '$clock ${_lower(spaced)}' : '$clock $spaced';
}

String _lower(String value) => value.toLowerCase();

/// `Tue 6 Oct 2026`
String formatDateLine(DateTime moment) {
  const weekdays = <String>['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
  const months = <String>[
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];
  return '${weekdays[moment.weekday - 1]} '
      '${moment.day} ${months[moment.month - 1]} ${moment.year}';
}

/// Short weekday letter for the stats bar chart.
String weekdayLetter(DateTime moment) {
  const weekdays = <String>['M', 'T', 'W', 'T', 'F', 'S', 'S'];
  return weekdays[moment.weekday - 1];
}

/// `1h 25m`, `25m`, `0m`
String formatDurationMinutes(int minutes) {
  if (minutes <= 0) return '0m';
  final hours = minutes ~/ 60;
  final rest = minutes % 60;
  if (hours == 0) return '${rest}m';
  if (rest == 0) return '${hours}h';
  return '${hours}h ${rest}m';
}
