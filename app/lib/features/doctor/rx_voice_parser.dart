// Phase 9 — voice prescription parser (Section 5.2 / D6).
//
// Deterministic, rule-based parsing of a dictated phrase into the D5
// structured prescription fields. NO AI involved. The result is ALWAYS shown
// to the doctor for review/edit before saving — never auto-saved (spec).
//
// Understood grammar (case-insensitive, any order after the drug name):
//   "<drug> [500 mg|5 ml|2 tablets] [morning/afternoon/night words |
//    once/twice/thrice a day] [before/after/with food] [for N days]"
// Examples:
//   "paracetamol 500 mg twice a day after food for 5 days"
//   "metformin five hundred mg morning and night with food for 30 days"

class ParsedPrescription {
  const ParsedPrescription({
    required this.drugName,
    this.dosage,
    required this.schedule,
    this.relationToFood, // 'before' | 'after' | 'with' | null
    this.durationDays,
  });

  final String drugName;
  final String? dosage;
  final Map<String, bool> schedule;
  final String? relationToFood;
  final int? durationDays;
}

const _numberWords = {
  'one': 1, 'two': 2, 'three': 3, 'four': 4, 'five': 5, 'six': 6,
  'seven': 7, 'eight': 8, 'nine': 9, 'ten': 10, 'fourteen': 14,
  'fifteen': 15, 'twenty': 20, 'thirty': 30, 'sixty': 60, 'ninety': 90,
};

int? _asNumber(String w) => int.tryParse(w) ?? _numberWords[w.toLowerCase()];

/// Parses a dictated prescription phrase. Returns null when no drug name can
/// be found (e.g. empty input).
ParsedPrescription? parseSpokenPrescription(String input) {
  var text = ' ${input.trim().toLowerCase()} ';
  if (text.trim().isEmpty) return null;

  final schedule = {'morning': false, 'afternoon': false, 'night': false};
  String? food;
  int? duration;
  String? dosage;

  // ---- duration: "for 5 days" / "for five days" ----
  final dur = RegExp(r'\bfor\s+([a-z0-9]+)\s+days?\b').firstMatch(text);
  if (dur != null) {
    duration = _asNumber(dur.group(1)!);
    if (duration != null) text = text.replaceFirst(dur.group(0)!, ' ');
  }

  // ---- food relation ----
  final foodM = RegExp(r'\b(before|after|with)\s+(food|meals?|breakfast|dinner)\b')
      .firstMatch(text);
  if (foodM != null) {
    food = foodM.group(1);
    text = text.replaceFirst(foodM.group(0)!, ' ');
  }

  // ---- frequency phrases -> slots ----
  final freqPatterns = <RegExp, List<String>>{
    RegExp(r'\b(once)\s+(a|per)\s+day\b|\bonce\s+daily\b|\bdaily\b'): ['morning'],
    RegExp(r'\b(twice)\s+(a|per)\s+day\b|\btwice\s+daily\b'): ['morning', 'night'],
    RegExp(r'\b(thrice|three\s+times)\s+(a|per)?\s*day\b'): [
      'morning', 'afternoon', 'night'
    ],
  };
  for (final e in freqPatterns.entries) {
    final m = e.key.firstMatch(text);
    if (m != null) {
      for (final s in e.value) {
        schedule[s] = true;
      }
      text = text.replaceFirst(m.group(0)!, ' ');
      break;
    }
  }
  // Explicit slot words ("morning and night", "evening" counts as night).
  for (final entry in {
    'morning': RegExp(r'\bmorning\b'),
    'afternoon': RegExp(r'\bafternoon\b|\bnoon\b'),
    'night': RegExp(r'\bnight\b|\bevening\b|\bbed\s*time\b'),
  }.entries) {
    if (entry.value.hasMatch(text)) {
      schedule[entry.key] = true;
      text = text.replaceAll(entry.value, ' ');
    }
  }
  text = text.replaceAll(RegExp(r'\b(and|at|in|the)\b'), ' ');

  // ---- dosage: "500 mg" / "five hundred mg" / "2 tablets" ----
  final doseM = RegExp(
          r'\b(\d+(?:\.\d+)?)\s*(mg|ml|mcg|g|iu|units?|tablets?|caps?(?:ules?)?|drops?|puffs?)\b')
      .firstMatch(text);
  if (doseM != null) {
    final unit = doseM.group(2)!;
    dosage = '${doseM.group(1)}$unit';
    text = text.replaceFirst(doseM.group(0)!, ' ');
  } else {
    // spoken numbers: "five hundred mg"
    final spoken = RegExp(
            r'\b([a-z]+)(\s+hundred)?\s*(mg|ml|mcg|g|units?|tablets?)\b')
        .firstMatch(text);
    if (spoken != null && _asNumber(spoken.group(1)!) != null) {
      final n = _asNumber(spoken.group(1)!)! * (spoken.group(2) != null ? 100 : 1);
      dosage = '$n${spoken.group(3)}';
      text = text.replaceFirst(spoken.group(0)!, ' ');
    }
  }

  // ---- whatever meaningful words remain lead with the drug name ----
  final words = text
      .split(RegExp(r'\s+'))
      .where((w) => w.isNotEmpty && RegExp(r'^[a-z][a-z0-9\-]*$').hasMatch(w))
      .toList();
  if (words.isEmpty) return null;
  final drug = words
      .map((w) => w[0].toUpperCase() + w.substring(1))
      .join(' ');

  return ParsedPrescription(
    drugName: drug,
    dosage: dosage,
    schedule: schedule,
    relationToFood: food,
    durationDays: duration,
  );
}
