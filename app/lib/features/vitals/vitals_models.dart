import 'package:flutter/material.dart';

/// An on-device health hub the patient can connect (epic §3). MVP = the two
/// free, on-device stores; `manual` covers hand-entered values (e.g. a BP cuff
/// reading) with no hub.
enum WearableProvider { appleHealth, healthConnect, manual }

extension WearableProviderX on WearableProvider {
  String get db => switch (this) {
        WearableProvider.appleHealth => 'apple_health',
        WearableProvider.healthConnect => 'health_connect',
        WearableProvider.manual => 'manual',
      };

  String get label => switch (this) {
        WearableProvider.appleHealth => 'Apple Health',
        WearableProvider.healthConnect => 'Health Connect',
        WearableProvider.manual => 'Manual entry',
      };

  String get blurb => switch (this) {
        WearableProvider.appleHealth => 'Apple Watch & iPhone health data',
        WearableProvider.healthConnect =>
          'Samsung, Noise, boAt, Fitbit, Garmin & more',
        WearableProvider.manual => 'Type in readings yourself',
      };

  IconData get icon => switch (this) {
        WearableProvider.appleHealth => Icons.favorite,
        WearableProvider.healthConnect => Icons.watch,
        WearableProvider.manual => Icons.edit,
      };

  static WearableProvider fromDb(String v) => switch (v) {
        'apple_health' => WearableProvider.appleHealth,
        'health_connect' => WearableProvider.healthConnect,
        _ => WearableProvider.manual,
      };
}

/// A connected source and whether it's live.
class VitalsConnection {
  const VitalsConnection({required this.provider, required this.connected});
  final WearableProvider provider;
  final bool connected;
}

/// Today's headline numbers for the patient's own daily view. Every field is a
/// raw device figure — nothing here is scored or interpreted (§6).
class DailyVitals {
  const DailyVitals({
    this.steps = 0,
    this.stepsGoal = 10000,
    this.activeMinutes = 0,
    this.activeGoal = 30,
    this.calories = 0,
    this.caloriesGoal = 500,
    this.restingHr,
    this.sleepMinutes,
    this.spo2,
    this.streakDays = 0,
  });

  final int steps;
  final int stepsGoal;
  final int activeMinutes;
  final int activeGoal;
  final int calories;
  final int caloriesGoal;
  final int? restingHr; // bpm
  final int? sleepMinutes;
  final int? spo2; // % — regulated, display-only
  final int streakDays;
}

/// One point on a week/month trend line.
class MetricPoint {
  const MetricPoint(this.date, this.value);
  final DateTime date;
  final double value;
}

/// A completed workout session (Strava-style feed).
class WorkoutSummary {
  const WorkoutSummary({
    required this.type,
    required this.startedAt,
    this.durationMin,
    this.distanceM,
    this.avgHr,
    this.calories,
  });

  final String type;
  final DateTime startedAt;
  final int? durationMin;
  final double? distanceM;
  final int? avgHr;
  final int? calories;
}
