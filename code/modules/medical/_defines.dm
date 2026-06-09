// Audiences a symptom can present to. A symptom may light up any subset
// of the three. Patient-only sensations rely on the player narrating;
// emotes are visible to anyone in view; scanner-visible vitals are read
// by instruments.
#define SYMPTOM_AUDIENCE_PATIENT   (1 << 0)
#define SYMPTOM_AUDIENCE_PUBLIC    (1 << 1)
#define SYMPTOM_AUDIENCE_SCANNER   (1 << 2)

// Severity bands. Conditions tick severity up to 100; cascades fire at
// thresholds, terminal conditions hit at 100. We surface bands to the
// scanner UI without leaking numeric severity to players.
#define CONDITION_SEVERITY_MILD       25
#define CONDITION_SEVERITY_MODERATE   50
#define CONDITION_SEVERITY_SEVERE     75
#define CONDITION_SEVERITY_TERMINAL  100

// Symptom presence rerolls when severity crosses an integer multiple of
// this value, so the patient's symptom set shifts as they deteriorate.
#define CONDITION_SYMPTOM_REROLL_STEP 30

// How much severity ticks up per Life() if the condition has no cure
// active. Per-condition `progression_rate` multiplies this.
//
// Tuned so that progression_rate = 1.0 takes ~10 minutes (~300 ticks at
// ~2s each) to climb from severity 0 to 100, including the
// (1 + severity/50) severity-acceleration multiplier in tick_condition.
// Math: integral from 0..100 of 1/(BASE * (1 + s/50)) ds = 50 ln(3) /
// BASE ≈ 55/BASE ticks. Solving for 300 ticks gives BASE ≈ 0.18.
#define CONDITION_BASE_PROGRESSION 0.18

// Reference dose for chemical cure-rate scaling. A condition's
// `cured_by[id] = rate` is the per-tick rate when the patient has
// exactly this volume in their body. Below the standard dose, the
// chem heals more slowly; above, more quickly — up to DQ_CHEM_DOSE_CAP.
// Most autoinjectors deliver around this much; 10u is a natural
// "single dose" reference point.
#define DQ_CHEM_STANDARD_DOSE 10

// Cure-rate ceiling. A chem at 4× standard dose (~40u) reaches full
// effective rate; pushing past that gains no extra healing and only
// accumulates overdose risk. Pure ramp from 0 (no chem) → 1 (standard
// dose) → 4 (cap dose).
#define DQ_CHEM_DOSE_CAP 4.0
