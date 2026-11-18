import 'package:flutter_test/flutter_test.dart';
import 'package:pomodoro_clock/src/services/zone_service.dart';
import 'package:timezone/data/latest.dart' as tz_data;

void main() {
  const service = ZoneService();

  setUpAll(tz_data.initializeTimeZones);

  group('search', () {
    test('matches by city name', () {
      expect(service.search('tokyo'), contains('Asia/Tokyo'));
      expect(service.search('Berlin'), contains('Europe/Berlin'));
    });

    test('matches with spaces or underscores', () {
      expect(service.search('new york'), contains('America/New_York'));
      expect(service.search('new_york'), contains('America/New_York'));
    });

    test('ranks an exact city match first', () {
      expect(service.search('new york').first, 'America/New_York');
    });

    test('empty query returns nothing', () {
      expect(service.search('   '), isEmpty);
    });

    test('nonsense query returns nothing', () {
      expect(service.search('zzzznotacity'), isEmpty);
    });
  });

  group('labels', () {
    test('city and region split', () {
      expect(service.cityOf('Asia/Tokyo'), 'Tokyo');
      expect(service.cityOf('America/New_York'), 'New York');
      expect(service.regionOf('America/Argentina/Buenos_Aires'), 'America');
    });

    test('whole-hour offsets drop the minutes', () {
      expect(ZoneService.offsetLabelFor(const Duration(hours: 9)), 'GMT+9');
      expect(ZoneService.offsetLabelFor(const Duration(hours: -5)), 'GMT-5');
      expect(ZoneService.offsetLabelFor(Duration.zero), 'GMT+0');
    });

    test('half-hour offsets keep the minutes', () {
      expect(
        ZoneService.offsetLabelFor(const Duration(hours: 5, minutes: 30)),
        'GMT+5:30',
      );
      expect(
        ZoneService.offsetLabelFor(const Duration(hours: -3, minutes: -30)),
        'GMT-3:30',
      );
    });
  });

  group('describe', () {
    test('Tokyo is nine hours ahead of UTC with no DST in October', () {
      final display = service.describe(
        'Asia/Tokyo',
        reference: DateTime.utc(2026, 10, 6, 0),
      );
      expect(display.city, 'Tokyo');
      expect(display.abbreviation, 'JST');
      expect(display.offsetLabel, 'GMT+9');
    });

    test(
      'New York shows daylight-saving offset and abbreviation in October',
      () {
        final display = service.describe(
          'America/New_York',
          reference: DateTime.utc(2026, 10, 6, 12),
        );
        expect(display.abbreviation, 'EDT');
        expect(display.offsetLabel, 'GMT-4');
      },
    );

    test('Kolkata renders a half-hour offset', () {
      final display = service.describe(
        'Asia/Kolkata',
        reference: DateTime.utc(2026, 10, 6, 12),
      );
      expect(display.offsetLabel, 'GMT+5:30');
      expect(display.time.hour, 17);
      expect(display.time.minute, 30);
    });

    test('the zoned wall clock is the same instant as the reference', () {
      final reference = DateTime.utc(2026, 10, 6, 12, 30);
      final tokyo = service.describe('Asia/Tokyo', reference: reference);
      expect(tokyo.time.hour, 21);
      expect(tokyo.time.minute, 30);
      expect(tokyo.dayDelta, 0);
    });

    test('a late reference pushes Tokyo into the next calendar day', () {
      final reference = DateTime.utc(2026, 10, 6, 16, 30);
      final tokyo = service.describe('Asia/Tokyo', reference: reference);
      expect(tokyo.dayDelta, 1);
      expect(tokyo.isAheadOfLocal, isTrue);
    });

    test('unknown zone names degrade instead of throwing', () {
      final display = service.describe('Mars/Olympus_Mons');
      expect(display.offsetLabel, 'unknown zone');
      expect(display.city, 'Olympus Mons');
      expect(display.dayDelta, 0);
    });
  });
}
