// Shared constants for the substance & chemistry system.
//
// The science core: every field-found material, bio extract, plant compound, and
// combination output is a /datum/substance with a *visible* surface behavior
// (effect family + trigger) and a *hidden* five-axis attribute profile that
// rerolls every round. The combination resolver (substance_resolver.dm) reads how
// two profiles relate and produces a result. See the design doc for the full model.

// ---- Attribute axes --------------------------------------------------------
// Four linear axes share one cap; resonance is cyclic on its own scale.
#define SUBSTANCE_ATTR_MAX   100 // energy / volatility / affinity / purity ceiling
#define SUBSTANCE_RES_MAX    360 // resonance is a cyclic 0..360 value

// ---- Resonance relationship (the character engine) -------------------------
// circular_distance(A.resonance, B.resonance) is 0..180; the band it lands in
// decides whether the reaction reinforces, transforms, or conflicts.
#define SUB_REL_MATCHING 1 // reinforce — same family, intensified, predictable
#define SUB_REL_ADJACENT 2 // transform — a new family is born (the creative band)
#define SUB_REL_OPPOSING 3 // conflict — instability, byproducts, hazard

#define SUB_MATCH_BAND 30  // res_delta <= this           -> MATCHING
#define SUB_ADJ_BAND   120 // MATCH_BAND < res_delta <= this -> ADJACENT; above -> OPPOSING

// ---- Effect families (the visible surface behavior) ------------------------
// 1-based so they index family_names()/family_default_trigger() directly. A
// substance's family is always known on acquisition; the transform map
// (substance_family_transform) maps a pair of families to a derived one.
#define SUBFAM_DISCHARGE 1 // arcing electric energy
#define SUBFAM_THERMAL   2 // heat / cold swing
#define SUBFAM_FORCE     3 // kinetic / gravitic shove
#define SUBFAM_FIELD     4 // barrier / forcefield
#define SUBFAM_SPORE     5 // biological bloom / spores
#define SUBFAM_CORROSIVE 6 // acidic / chemical breakdown
#define SUBFAM_RADIANT   7 // radiation / hard light
#define SUBFAM_VOID      8 // entropic / bluespace tear
#define SUBFAM_COUNT     8

// ---- Triggers (when the surface behavior fires) ----------------------------
// Reuse the xenoarch trigger vocabulary in spirit; a substance fires its effect
// wherever its trigger condition is met in its final form (blade, ammo, tile...).
#define SUB_TRIG_IMPACT   1 // on a physical strike / bullet
#define SUB_TRIG_HEAT     2 // on reaching high temperature
#define SUB_TRIG_PRESSURE 3 // on a pressure spike
#define SUB_TRIG_ENERGY   4 // on an energy / EM pulse
#define SUB_TRIG_CONTACT  5 // on touch / reagent contact
#define SUB_TRIG_COUNT    5

// ---- Resolver tuning -------------------------------------------------------
// Energy (magnitude) modifier per relationship. OPPOSING routes most energy into
// the hazard, so its output keeps only a remnant.
#define SUB_EMOD_MATCH     1.2
#define SUB_EMOD_ADJ       1.0
#define SUB_EMOD_OPPOSING  0.4

// Volatility (control) penalty added when the substances conflict.
#define SUB_OPPOSING_VOLATILITY_PENALTY 25

// Byproduct frequency multiplier: matching is clean, opposing is filthy.
#define SUB_BYMOD_MATCH    0.5
#define SUB_BYMOD_ADJ      1.0
#define SUB_BYMOD_OPPOSING 1.8

// Purity (cleanliness) is further degraded when the substances conflict.
#define SUB_OPPOSING_PURITY_FACTOR 0.6

// Asymmetric-affinity dampening: when affinities differ by more than this, the
// low-affinity partner tames the mix (reduces effective magnitude and volatility).
#define SUB_AFFINITY_ASYMMETRY 40

// A conflict erupts into a hazard when its magnitude AND volatility both clear
// these thresholds. Severity then scales with the magnitude.
#define SUB_HAZARD_M_THRESHOLD 60
#define SUB_HAZARD_V_THRESHOLD 60

// ---- Manufacturing integration ---------------------------------------------
// A material item forged from a substance material emits this when one of its
// form's trigger conditions is met (a melee strike, a thrown impact, ...). The
// /datum/component/substance_infusion on the item listens and fires the effect if
// the substance's own trigger matches the condition.
// Args: (datum/source, condition /* SUB_TRIG_* */, turf/where, atom/cause)
#define COMSIG_SUBSTANCE_FORM_TRIGGER "substance_form_trigger"
// Default number of times a forged item can discharge its infused effect before
// the infusion is spent (the base item stays usable).
#define SUBSTANCE_INFUSION_CHARGES 6
// Minimum delay between an infused item's discharges.
#define SUBSTANCE_INFUSION_COOLDOWN (2 SECONDS)
