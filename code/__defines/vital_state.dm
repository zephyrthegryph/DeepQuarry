// Vital state: death, revival and the named vitality bands.
// See code/modules/body/vital_state.dm, code/modules/body/revival.dm and code/modules/mob/death.dm.

// --- return_from_death() flags ---------------------------------------------------------------

/// fully_heal() before the eligibility checks (admin revive, rejuvenate-style magic).
#define REVIVE_HEAL (1<<0)
/// Skip the brain revival window (defib timer, brain-stem, husk, vital organs). Lethal injury still refuses.
#define REVIVE_IGNORE_WINDOW (1<<1)
/// Keep timeofdeath (and the identity's time of death) as they were.
#define REVIVE_KEEP_TIMEOFDEATH (1<<2)
/// Land unconscious; Life() brings the patient round when vitals allow (defib, CPR).
#define REVIVE_UNCONSCIOUS (1<<3)
/// Rebuild whatever would refuse: missing vital organs (brain included), brain death and decay,
/// husking and brain-stem damage, then heal. With REVIVE_IGNORE_WINDOW the revive cannot refuse
/// a dead, undeleted mob. Used by vore reform, which must always succeed.
#define REVIVE_RESTORE (1<<4)

// --- Vitality bands (L.vital_band()) ---------------------------------------------------------
// Ordered worst to best, so `vital_band() <= VITAL_BAND_CRITICAL` reads "critical or worse".

#define VITAL_BAND_DEAD 0
/// Alive, but the body's injuries are lethal (death is pending the next status check) or vitality is spent.
#define VITAL_BAND_DYING 1
/// Down from injury (unconscious with TRAIT_CRITICAL_CONDITION).
#define VITAL_BAND_CRITICAL 2
/// Conscious, vitality at or below VITALITY_SERIOUS.
#define VITAL_BAND_SERIOUS 3
/// Conscious, vitality at or below VITALITY_HURT.
#define VITAL_BAND_HURT 4
#define VITAL_BAND_HEALTHY 5

/// vitality() at or below this is "seriously hurt" (the old 0.33 AI-flee / boss thresholds).
#define VITALITY_SERIOUS 0.33
/// vitality() at or below this is "hurt" (the old 0.5 thresholds).
#define VITALITY_HURT 0.5
