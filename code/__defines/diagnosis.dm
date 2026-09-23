// Diagnosis defines. See code/modules/medical/diagnosis/ and
// doc/health_system_review.md §5.8.

// --- Presentation / senses ------------------------------------------------------
// How an affliction presents (`/datum/affliction/var/presentation`), and what
// an instrument can perceive (`/datum/diagnostic_profile/var/senses`). A
// finding reaches a report when the two overlap.
/// Visible to the naked eye: examine, a glance, a medical HUD.
#define PRESENT_VISIBLE   (1<<0)
/// Felt by hand: grab inspection / palpation.
#define PRESENT_PALPATION (1<<1)
/// Surface sensors: any health analyzer (skin, blood gases, pulse oximetry).
#define PRESENT_SURFACE   (1<<2)
/// Internal imaging: advanced analyzers and the body scanner.
#define PRESENT_INTERNAL  (1<<3)
/// Laboratory / deep imaging: body scanner and phasic analyzers only. The
/// "run the right test" tier.
#define PRESENT_LAB       (1<<4)
/// Synthetic diagnostic bus: cyborg analyzers, robot self-diagnosis.
#define PRESENT_SYNTHETIC (1<<5)
/// Nanite swarm telemetry.
#define PRESENT_NANITE    (1<<6)
#define PRESENT_ALL       (PRESENT_VISIBLE | PRESENT_PALPATION | PRESENT_SURFACE | PRESENT_INTERNAL | PRESENT_LAB | PRESENT_SYNTHETIC | PRESENT_NANITE)

// --- Vitals an instrument can read ------------------------------------------------
#define VITALS_PULSE         (1<<0)
#define VITALS_BP            (1<<1)
#define VITALS_SPO2          (1<<2)
#define VITALS_TEMP          (1<<3)
#define VITALS_RESP          (1<<4)
#define VITALS_CONSCIOUSNESS (1<<5)
#define VITALS_ALL           (VITALS_PULSE | VITALS_BP | VITALS_SPO2 | VITALS_TEMP | VITALS_RESP | VITALS_CONSCIOUSNESS)

// --- Part detail ------------------------------------------------------------------
#define DIAG_PARTS_NONE  0
/// Per-part qualitative band.
#define DIAG_PARTS_BANDS 1

// --- Patient status (one per report) ------------------------------------------------
#define DIAG_STATUS_ALIVE    "alive"
#define DIAG_STATUS_CRITICAL "critical"
#define DIAG_STATUS_DEAD     "dead"

// --- Severity bands (strings: shared with the TGUI) -----------------------------------
#define DIAG_BAND_NONE     "uninjured"
#define DIAG_BAND_MINOR    "minor"
#define DIAG_BAND_MODERATE "moderate"
#define DIAG_BAND_SEVERE   "severe"
#define DIAG_BAND_CRITICAL "critical"

// --- Finding kinds ----------------------------------------------------------------------
#define DIAG_FINDING_CONDITION "condition"
#define DIAG_FINDING_SIGN      "sign"
#define DIAG_FINDING_LESION    "lesion"
#define DIAG_FINDING_WOUND     "wound"
