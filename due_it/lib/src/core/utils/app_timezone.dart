import 'package:timezone/data/latest.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;
import 'package:flutter_timezone/flutter_timezone.dart';

class AppTimezone {
  static const String businessTimezone = 'Asia/Kolkata';
  static late tz.Location businessLocation;

  static Future<void> initialize() async {
    tz_data.initializeTimeZones();
    businessLocation = tz.getLocation(businessTimezone);
  }

  static tz.TZDateTime businessNow() {
    return tz.TZDateTime.now(businessLocation);
  }

  static tz.TZDateTime businessDate() {
    final now = businessNow();
    return tz.TZDateTime(businessLocation, now.year, now.month, now.day);
  }

  static DateTime createBusinessEventTime(int year, int month, int day, int hour, int minute) {
    final tzTime = tz.TZDateTime(businessLocation, year, month, day, hour, minute);
    return tzTime.toUtc();
  }

  static String dateKey(DateTime utcTimestamp) {
    final tzTime = tz.TZDateTime.from(utcTimestamp, businessLocation);
    final y = tzTime.year.toString().padLeft(4, '0');
    final m = tzTime.month.toString().padLeft(2, '0');
    final d = tzTime.day.toString().padLeft(2, '0');
    return '$y-$m-$d';
  }
  
  static String todayDateKey() {
    final now = businessNow();
    final y = now.year.toString().padLeft(4, '0');
    final m = now.month.toString().padLeft(2, '0');
    final d = now.day.toString().padLeft(2, '0');
    return '$y-$m-$d';
  }
}
