// Drug profile defines: what a drug hides from instruments (`/datum/reagent/var/hides`) and how long it must be in the blood to do so.
// The other two drawbacks are declared elsewhere: a strain is `strains = alist(O_* = rate)` on the reagent (code/content/reagents/drug_profile.dm),
// an added symptom is a /datum/affliction/chem_side_effect (or nausea / seizure) with `caused_by_chems`.

/// Reading keys a drug can mask on a scan, a HUD or a monitor (`hides = list(HIDE_*)`).
#define HIDE_PAIN "pain"                              // the patient's pain level and every pain finding
#define HIDE_PAIN_LOCATION "pain_location"            // where it hurts: findings lose their location
#define HIDE_ORGAN_MILD "organ_mild"                  // mild organ damage (minor findings and minor part bands)
#define HIDE_PULSE_IRREGULAR "pulse_irregular"        // an irregular rhythm reads as sinus
#define HIDE_INTERNAL_BLEEDING "internal_bleeding"    // internal haemorrhage findings
#define HIDE_LUNG_HEART "lung_heart"                  // lung and heart damage findings and part bands
#define HIDE_FEVER "fever"                            // the temperature reads normal
#define HIDE_SYMPTOM_SUPPRESSION "symptom_suppression" // withdrawal and similar signs (suppresses withdrawal)

/// Units of a masking drug in the blood below which it hides nothing.
#define DRUG_HIDE_MIN_VOLUME 1

/// A strain heals on its own while the organ is healthy; this is the damage per unit metabolised that a standard strain row means (the tables use small multiples of it).
#define DRUG_STRAIN_MILD 0.02
#define DRUG_STRAIN_MODERATE 0.05
#define DRUG_STRAIN_HEAVY 0.12

/// A clot risk (`clot_risk`) applies while the heart's damage is at least this share of its maximum, or the systolic pressure is under DRUG_CLOT_LOW_SYSTOLIC (mmHg).
#define DRUG_CLOT_HEART_DAMAGE_FRACTION 0.25
#define DRUG_CLOT_LOW_SYSTOLIC 90
/// Ischemic damage one clot leaves on the brain or the heart.
#define DRUG_CLOT_ISCHEMIC_DAMAGE 12

/// Blindness a flash adds per point that STAT_FLASH_VULNERABILITY is above 1 (a standard flash blinds for 5).
#define FLASH_VULNERABILITY_BLIND 5

/// Pain per unit of sterilizine that touches skin.
#define STERILIZINE_STING_PER_UNIT 0.5

/// Kelvin per REM that an overdose of leporazine pushes the body temperature away from normal.
#define LEPORAZINE_OVERDOSE_KELVIN_PER_REM 15
