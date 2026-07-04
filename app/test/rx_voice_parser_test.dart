import 'package:carebridge/features/doctor/rx_voice_parser.dart';
import 'package:flutter_test/flutter_test.dart';

/// Phase 9 — deterministic voice-prescription parser (D6). No AI, no network:
/// pure rules from dictated text to D5 structured fields. The UI always shows
/// the result for doctor review before saving.
void main() {
  test('full phrase: drug, dosage, twice a day, food, duration', () {
    final p = parseSpokenPrescription(
        'paracetamol 500 mg twice a day after food for 5 days')!;
    expect(p.drugName, 'Paracetamol');
    expect(p.dosage, '500mg');
    expect(p.schedule, {'morning': true, 'afternoon': false, 'night': true});
    expect(p.relationToFood, 'after');
    expect(p.durationDays, 5);
  });

  test('explicit slots and spoken number duration', () {
    final p = parseSpokenPrescription(
        'metformin 500 mg morning and night with food for thirty days')!;
    expect(p.drugName, 'Metformin');
    expect(p.schedule['morning'], isTrue);
    expect(p.schedule['afternoon'], isFalse);
    expect(p.schedule['night'], isTrue);
    expect(p.relationToFood, 'with');
    expect(p.durationDays, 30);
  });

  test('three times a day, tablets dosage', () {
    final p = parseSpokenPrescription(
        'amoxicillin 2 tablets three times a day before meals for seven days')!;
    expect(p.drugName, 'Amoxicillin');
    expect(p.dosage, '2tablets');
    expect(p.schedule.values.every((v) => v), isTrue);
    expect(p.relationToFood, 'before');
    expect(p.durationDays, 7);
  });

  test('evening maps to night; once daily maps to morning', () {
    final p1 = parseSpokenPrescription('cetirizine 10 mg in the evening')!;
    expect(p1.schedule['night'], isTrue);
    final p2 = parseSpokenPrescription('vitamin d once daily')!;
    expect(p2.schedule['morning'], isTrue);
  });

  test('drug only — everything else null/empty', () {
    final p = parseSpokenPrescription('azithromycin')!;
    expect(p.drugName, 'Azithromycin');
    expect(p.dosage, isNull);
    expect(p.durationDays, isNull);
    expect(p.schedule.values.any((v) => v), isFalse);
  });

  test('empty and garbage input return null', () {
    expect(parseSpokenPrescription(''), isNull);
    expect(parseSpokenPrescription('   '), isNull);
  });
}
