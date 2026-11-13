// Defines for the drug-rework core: diagnosis masking subcategories, seizures, nausea and crooked-bone healing.

// --- Symptom subcategories the diagnosis masks (a drug's `hides = list(HIDE_*)`, code/content/medical/diagnosis/diagnose.dm) ---
/// A pain symptom: HIDE_PAIN drops its sign finding from instruments, HIDE_PAIN_LOCATION removes where it hurts.
#define SYMPTOM_SUBCATEGORY_PAIN "Pain"
/// A withdrawal sign: HIDE_SYMPTOM_SUPPRESSION drops it from instruments.
#define SYMPTOM_SUBCATEGORY_WITHDRAWAL "Withdrawal"

// --- Seizures (/datum/affliction/seizure, stat STAT_SEIZURE_PRONENESS) ---
/// The shock a body with no proneness would need to seize: far above any real shock, so it never does.
#define SEIZURE_BASE_THRESHOLD 100
/// Threshold points one point of seizure_proneness takes off.
#define SEIZURE_PRONENESS_SCALE 10
/// Chance in percent per point of proneness that a shock above the threshold seizes (capped at 100).
#define SEIZURE_CHANCE_PER_PRONENESS 10
/// An electric injury applying less than this never seizes anyone.
#define SEIZURE_MIN_SHOCK 5

// --- Nausea (/datum/affliction/nausea) ---
/// Below this severity the patient only feels queasy and never vomits.
#define NAUSEA_VOMIT_MIN_SEVERITY 25
/// Chance in percent per condition tick, per point of severity, that the patient vomits (8 at severity 100).
#define NAUSEA_VOMIT_CHANCE_PER_SEVERITY 0.08
