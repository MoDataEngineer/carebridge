// Suggestion lists for the patient profile pickers (Section 5.1) — common
// allergies and chronic conditions, so patients tap instead of typing.
// Searchable in the UI; free text stays allowed so an unlisted entry never
// blocks saving a profile (mirrors kMedicalSpecialties).

/// Frequently-reported allergies — drug classes, foods, and environmental.
const List<String> kCommonAllergies = [
  'Penicillin',
  'Sulfa drugs (Sulfonamides)',
  'Aspirin',
  'NSAIDs (Ibuprofen/Diclofenac)',
  'Cephalosporins',
  'Iodine / Contrast dye',
  'Local anaesthetic (Lignocaine)',
  'Peanuts',
  'Tree nuts',
  'Milk / Dairy',
  'Eggs',
  'Soy',
  'Wheat / Gluten',
  'Shellfish',
  'Fish',
  'Sesame',
  'Dust mites',
  'Pollen',
  'Pet dander',
  'Mould',
  'Insect stings (Bee/Wasp)',
  'Latex',
];

/// Frequently-reported chronic conditions seen in Indian primary care.
const List<String> kCommonChronicConditions = [
  'Diabetes (Type 2)',
  'Diabetes (Type 1)',
  'Hypertension (High BP)',
  'High cholesterol (Dyslipidaemia)',
  'Asthma',
  'COPD',
  'Thyroid disorder (Hypothyroidism)',
  'Thyroid disorder (Hyperthyroidism)',
  'Coronary artery disease',
  'Chronic kidney disease',
  'Fatty liver disease',
  'Arthritis (Osteoarthritis)',
  'Rheumatoid arthritis',
  'Migraine',
  'Epilepsy',
  'Depression',
  'Anxiety disorder',
  'PCOS',
  'Anaemia',
  'Acid reflux (GERD)',
  'Tuberculosis (past/current)',
  'Cancer (past/current)',
];
