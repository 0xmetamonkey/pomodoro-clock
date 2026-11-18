import 'package:timezone/timezone.dart' as tz;

/// A timezone choice ready to render.
class ZoneDisplay {
  const ZoneDisplay({
    required this.name,
    required this.city,
    required this.time,
    required this.offsetLabel,
    required this.abbreviation,
    required this.dayDelta,
  });

  final String name;
  final String city;
  final tz.TZDateTime time;

  /// e.g. `GMT+05:30`
  final String offsetLabel;

  /// Zone abbreviation, e.g. `JST` or `CEST` (which already implies DST).
  final String abbreviation;

  /// Whole days between this zone's calendar date and the local one.
  final int dayDelta;

  bool get isAheadOfLocal => dayDelta > 0;

  bool get isBehindLocal => dayDelta < 0;
}

/// Thin wrapper over the IANA database so the UI never touches package:timezone
/// internals and DST is handled for us.
class ZoneService {
  const ZoneService();

  static const int _maxResults = 40;

  /// Zone names matching a free-text query (`tokyo`, `new york`, `berlin`).
  List<String> search(String query) {
    final needle = query.trim().toLowerCase();
    if (needle.isEmpty) return const <String>[];
    final normalized = needle.replaceAll('_', ' ');
    final matches = <String, String>{};
    for (final name in _searchableNames()) {
      final city = cityOf(name).toLowerCase();
      final region = name.toLowerCase();
      if (city.contains(normalized) || region.contains(normalized)) {
        matches[name] = name;
      }
      if (matches.length >= _maxResults) break;
    }
    final results = matches.keys.toList()
      ..sort((a, b) {
        // Prefer exact city matches, then prefix, then the rest.
        final scoreA = _score(a, normalized);
        final scoreB = _score(b, normalized);
        if (scoreA != scoreB) return scoreB.compareTo(scoreA);
        return cityOf(a).compareTo(cityOf(b));
      });
    return results.take(_maxResults).toList(growable: false);
  }

  int _score(String name, String needle) {
    final city = cityOf(name).toLowerCase();
    if (city == needle) return 3;
    if (city.startsWith(needle)) return 2;
    if (city.contains(needle)) return 1;
    return 0;
  }

  /// `Asia/Tokyo` -> `Tokyo`, `America/New_York` -> `New York`.
  String cityOf(String name) {
    final tail = name.contains('/') ? name.split('/').last : name;
    return tail.replaceAll('_', ' ');
  }

  String regionOf(String name) {
    final parts = name.split('/');
    return parts.length > 1 ? parts.first : '';
  }

  /// Renders the current wall-clock time for [name] relative to [reference].
  ///
  /// [reference] is the local wall clock the app is displaying, used only to
  /// compute the "ahead/behind a day" badge.
  ZoneDisplay describe(String name, {DateTime? reference}) {
    final now = reference ?? DateTime.now();
    final location = tz.timeZoneDatabase.locations[name];
    if (location == null) {
      // Unknown/stale entry: show the raw name rather than throwing.
      final fallback = tz.TZDateTime.from(now, tz.UTC);
      return ZoneDisplay(
        name: name,
        city: cityOf(name),
        time: fallback,
        offsetLabel: 'unknown zone',
        abbreviation: '??',
        dayDelta: 0,
      );
    }
    final zoned = tz.TZDateTime.from(now, location);
    return ZoneDisplay(
      name: name,
      city: cityOf(name),
      time: zoned,
      offsetLabel: offsetLabelFor(zoned.timeZoneOffset),
      abbreviation: zoned.timeZoneName,
      // Compared against the machine's own local calendar date.
      dayDelta: _dayDelta(zoned, now.year, now.month, now.day),
    );
  }

  /// `GMT+05:30`, shortened to `GMT+9` for whole-hour offsets.
  static String offsetLabelFor(Duration offset) {
    final sign = offset.isNegative ? '-' : '+';
    final abs = offset.abs();
    final hours = abs.inHours;
    final minutes = abs.inMinutes % 60;
    if (minutes == 0) return 'GMT$sign$hours';
    return 'GMT$sign$hours:${minutes.toString().padLeft(2, '0')}';
  }

  /// Difference in calendar days between the zoned moment and the local date.
  int _dayDelta(
    tz.TZDateTime moment,
    int localYear,
    int localMonth,
    int localDay,
  ) {
    final zoneDate = DateTime(moment.year, moment.month, moment.day);
    final localDate = DateTime(localYear, localMonth, localDay);
    return zoneDate.difference(localDate).inDays;
  }
}

List<String>? _nameCache;

/// Zone names offered by the picker, memoised after the first search.
///
/// An empty list is never cached, so a search attempted before
/// `initializeTimeZones()` still works once the database is loaded.
List<String> _searchableNames() {
  final cached = _nameCache;
  if (cached != null) return cached;
  final names =
      tz.timeZoneDatabase.locations.keys
          .where((name) => !name.startsWith('Etc/'))
          .toList()
        ..sort();
  if (names.isNotEmpty) _nameCache = names;
  return names;
}
