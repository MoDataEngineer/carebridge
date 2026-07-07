import 'package:flutter/material.dart';

/// One consultation session in a doctor's recurring weekly schedule
/// (migration 0025). Times are stored as 'HH:mm'. [dayOfWeek] follows Postgres
/// dow: 0 = Sunday … 6 = Saturday.
class DoctorSession {
  DoctorSession({
    this.id,
    required this.dayOfWeek,
    this.label,
    required this.start,
    required this.end,
    this.capacity = 20,
  });

  final String? id;
  final int dayOfWeek;
  String? label;
  TimeOfDay start;
  TimeOfDay end;
  int capacity;

  static TimeOfDay _parse(String s) {
    final parts = s.split(':');
    return TimeOfDay(
      hour: int.tryParse(parts[0]) ?? 9,
      minute: parts.length > 1 ? (int.tryParse(parts[1]) ?? 0) : 0,
    );
  }

  static String fmt(TimeOfDay t) =>
      '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

  factory DoctorSession.fromMap(Map<String, dynamic> m) => DoctorSession(
        id: m['id'] as String?,
        dayOfWeek: (m['day_of_week'] ?? 0) as int,
        label: m['label'] as String?,
        start: _parse((m['start_time'] ?? '09:00').toString()),
        end: _parse((m['end_time'] ?? '12:00').toString()),
        capacity: (m['capacity'] ?? 20) as int,
      );

  Map<String, dynamic> toJson() => {
        'day_of_week': dayOfWeek,
        'label': label,
        'start_time': fmt(start),
        'end_time': fmt(end),
        'capacity': capacity,
      };

  DoctorSession copyForDay(int day) => DoctorSession(
        dayOfWeek: day,
        label: label,
        start: start,
        end: end,
        capacity: capacity,
      );
}

/// Weekday names indexed by Postgres dow (0 = Sunday).
const List<String> kWeekdayNames = [
  'Sunday',
  'Monday',
  'Tuesday',
  'Wednesday',
  'Thursday',
  'Friday',
  'Saturday',
];

/// Display order — Monday first, Sunday last (matches how clinics think).
const List<int> kWeekOrder = [1, 2, 3, 4, 5, 6, 0];
