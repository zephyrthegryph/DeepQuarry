// Surgery defines. See code/modules/surgery/surgery.dm.

// --- Access depth -----------------------------------------------------------------
// How far a limb is opened. The depth is the state of the limb's
// /datum/affliction/surgical_incision; the limb's `open` var is a cache of it.
// Synthetic limbs use the same ladder: an unscrewed panel is INCISION_MADE,
// an open hatch FLESH_RETRACTED.
#define SURGERY_DEPTH_CLOSED 0
#define INCISION_MADE 1
#define FLESH_RETRACTED 2
#define BONE_CUT 2.5
#define BONE_RETRACTED 3

// --- Step phases (display and ordering) ---------------------------------------------
#define SURGERY_PHASE_ACCESS  "access"
#define SURGERY_PHASE_OPERATE "operate"
#define SURGERY_PHASE_CLOSE   "close"

// --- Where a step's treatments land -----------------------------------------------------
/// The limb itself (wounds, the incision, limb afflictions).
#define SURGERY_SCOPE_PART   1
/// The limb and every internal organ in it (regional procedures).
#define SURGERY_SCOPE_REGION 2
/// One internal organ in the limb, chosen by the surgeon.
#define SURGERY_SCOPE_ORGAN  3

// --- can_use() results ----------------------------------------------------------------------
/// The step matches the tool, but something is wrong; the step said why.
#define SURGERY_REFUSED -1

// --- Outcome tuning --------------------------------------------------------------------------
/// Worst success multiplier from a conscious patient feeling the whole step.
#define SURGERY_PAIN_PENALTY 0.4
/// Success multiplier for a surgeon outside the medical department.
#define SURGERY_UNTRAINED_MULT 0.8
/// Success multiplier for operating on yourself.
#define SURGERY_SELF_MULT 0.75
/// Success multiplier on the floor (surface cleanliness 0); an operating table is 1.
#define SURGERY_FLOOR_SURFACE_MULT 0.75

// --- Incision tuning --------------------------------------------------------------------------
/// Germs an open incision gathers per tick at zero sterility, per access depth.
#define INCISION_GERMS_PER_DEPTH 0.5
/// Severity of the incision affliction per access depth (display, pain).
#define INCISION_SEVERITY_PER_DEPTH 25
