// Dart mirrors of the Postgres enums in supabase/migrations/0001_init.sql.
// Kept in one place so app code and schema stay in lockstep.

enum SubscriptionStatus { free, paid }

enum DiagnosticType { lab, imaging, both }

enum TestStatus { ordered, sampleCollected, inProgress, reportReady, cancelled }

enum ReportType { pdf, image, structured }

/// D4: one_time is RESERVED/UNUSED in MVP (kept for a future share-once option).
enum GrantType { standing, oneTime, orderScoped }

enum GrantTargetType { doctor, diagnosticPartner }

enum GrantStatus { active, revoked, expired, pending }

/// Distinguishes clinic_admin access in the audit log (Section 10).
enum AccessorType { doctor, clinicAdmin, diagnosticPartner }

/// D5: structured prescription scheduling.
enum FoodRelation { before, after, withFood, none }

/// D2: scope claim carried in the minted JWT.
enum ActiveRole { doctor, admin }
