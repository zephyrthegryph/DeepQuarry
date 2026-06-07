// Cause framework — the universal "what produces a condition" abstraction.
//
// Every condition in the cascading-medical system arises from one of a
// small set of cause kinds:
//
//   damage_event      — a wound was created of a given type and severity
//   organ_damage      — an organ crossed a damage-percentage threshold
//   severity_gate     — a parent condition crossed a severity threshold
//   blood_loss        — vessel blood fell below a fraction
//   germ_level        — an organ's germ_level crossed a threshold
//
// Each /datum/dq_cause subtype carries its triggering rule data and a
// `produces` list of (condition_type, chance_or_band) records. The
// downstream dispatchers (cascades.dm for damage_event, emergent.dm for
// organ_damage, tick_condition for severity_gate, etc.) walk their
// relevant subset and fire spawns. The reference book reads the same
// data so the in-game documentation always matches behaviour.
//
// Authors register a cause once; both the runtime and the book pick it
// up. There is no separate "cascade table" — `cause.produces` is the
// table.

/datum/dq_cause
	/// Display name in the book.
	var/name = "cause"
	/// Reference-book category. Used for grouping in the Causes tab:
	///   "Trauma"        — damage events from injury
	///   "Complication"  — progressed from another condition
	///   "Environmental" — from external state (cold, low oxygen, ...)
	///   "Infection"     — germ-driven, including the wound→sepsis chain
	var/category = "Trauma"
	/// Optional finer grouping rendered as a grey subheader in the
	/// book index. Use to cluster related causes inside a category —
	/// e.g. "Blunt impact" groups every cause whose subcategory is
	/// that string. Null = no subgroup.
	var/subcategory
	/// One-sentence textbook overview. Required for non-condition causes
	/// (damage_event, blood_loss, etc.); on causes whose "kind" is
	/// already self-explanatory (severity_gate from another condition)
	/// the book uses the source condition's description instead.
	var/description = ""
	/// list of /datum/dq_cause_outcome describing each condition this
	/// cause can spawn. Authored by subtype New().
	var/list/produces


/datum/dq_cause/proc/setup()
	produces = list()


/datum/dq_cause/New()
	setup()


/// Helper for subtype authors. Adds a (condition, chance, requires,
/// threshold, tier) outcome to `produces`. `chance` is a probability
/// in 0..100. `threshold` lets organ_damage causes set a per-outcome
/// damage % (so one cause can have Moderate / Severe / Critical
/// outcomes at different organ-damage levels). `tier` is the book's
/// label for that bucket.
/datum/dq_cause/proc/declare(condition_type, chance = 100, requires_present = null, requires_absent = null, threshold = null, tier = null)
	produces += list(new /datum/dq_cause_outcome(condition_type, chance, requires_present, requires_absent, threshold, tier))


// --- Outcome record -----------------------------------------------------

/datum/dq_cause_outcome
	var/condition_type
	/// % chance per qualifying event (damage_event causes) or unused for
	/// gate-style causes where the condition is either present or not.
	var/chance = 100
	var/requires_present
	var/requires_absent
	/// Per-outcome organ-damage threshold (overrides the cause's
	/// threshold_pct, which is now just a default). Used by
	/// /datum/dq_cause/organ_damage to declare multiple severity tiers
	/// in a single cause: Moderate / Severe / Critical, each producing
	/// a different downstream condition.
	var/threshold
	/// Book-side label for which tier this outcome belongs to
	/// ("Moderate", "Severe", "Critical", ...). Null for non-tiered
	/// outcomes.
	var/tier

/datum/dq_cause_outcome/New(condition_type, chance, requires_present, requires_absent, threshold, tier)
	src.condition_type = condition_type
	src.chance = chance
	src.requires_present = requires_present
	src.requires_absent = requires_absent
	src.threshold = threshold
	src.tier = tier

/datum/dq_cause_outcome/proc/preconditions_met(obj/item/organ/target)
	if(requires_present || requires_absent)
		if(!target)
			return FALSE
		var/has_present = FALSE
		var/has_absent = FALSE
		for(var/datum/medical_issue/condition/C in target.medical_issues)
			if(requires_present && istype(C, requires_present))
				has_present = TRUE
			if(requires_absent && istype(C, requires_absent))
				has_absent = TRUE
		if(requires_present && !has_present)
			return FALSE
		if(requires_absent && has_absent)
			return FALSE
	return TRUE


// --- Subtype: damage_event ----------------------------------------------
//
// Authored once per "kind of injury": blunt to torso, sharp to limb,
// burn to head, etc. /obj/item/organ/external/createwound() flows
// through dq_dispatch_damage_event() which walks every matching
// damage_event cause and rolls its outcomes.

/datum/dq_cause/damage_event
	category = "Trauma"
	/// "blunt", "sharp", or "burn". Compared against the wound class
	/// derived in dispatcher from upstream CUT / PIERCE / BRUISE / BURN.
	var/wound_class
	/// Body region filter. Null = any. Else a list of organ_tags
	/// (BP_TORSO, BP_HEAD, BP_L_ARM, ...) or one of the named groups
	/// "limb" / "any_torso" handled by matches().
	var/list/body_regions
	/// Minimum single-event damage to qualify.
	var/min_damage = 1
	/// Minimum cumulative damage on the organ post-event to qualify.
	/// 0 = ignore cumulative. Used for burn shock and similar where
	/// the threshold is total burn_dam, not per-hit.
	var/min_cumulative_damage = 0


/datum/dq_cause/damage_event/proc/matches(wound_type, organ_tag, single_damage, cumulative_damage)
	if(wound_class && wound_type != wound_class)
		return FALSE
	if(single_damage < min_damage)
		return FALSE
	if(min_cumulative_damage && cumulative_damage < min_cumulative_damage)
		return FALSE
	if(length(body_regions))
		if(!_region_matches(organ_tag))
			return FALSE
	return TRUE

/datum/dq_cause/damage_event/proc/_region_matches(organ_tag)
	for(var/region in body_regions)
		if(region == organ_tag)
			return TRUE
		if(region == "limb" && _dq_is_limb_tag(organ_tag))
			return TRUE
	return FALSE


// --- Subtype: organ_damage ----------------------------------------------

/datum/dq_cause/organ_damage
	category = "Complication"
	/// Organ tag to watch (BP_* or O_*).
	var/organ
	/// Percent of max_damage that triggers the condition. The same
	/// number drives auto-cure on drop-below.
	var/threshold_pct


// --- Subtype: severity_gate ---------------------------------------------
//
// Replaces the previous cascade_at + cascade_to vars on each condition.
// When the source condition's severity climbs past `threshold`, the
// gated condition is rolled (or, with requires_absent / requires_present,
// branched).

/datum/dq_cause/severity_gate
	category = "Complication"
	/// Source condition typepath whose severity drives this gate.
	var/source_condition
	/// Severity threshold (0..100). At or above, the gate is open and
	/// any outcome that hasn't already fired rolls each tick until it
	/// does, exactly the same retry behaviour the old fire_cascade
	/// loop had.
	var/threshold


// --- Subtype: blood_loss ------------------------------------------------
//
// Reserved for future use. Existing blood-loss-driven cascades —
// hypovolemic_shock from internal_hemorrhage via a severity_gate, and
// the staged brain_damage / heart_damage conditions driven via
// organ_damage from oxyloss — don't need a dedicated cause kind yet;
// this slot is here so a future "patient's blood volume fell below X"
// rule has a place to live without another framework change.

/datum/dq_cause/blood_loss
	category = "Environmental"
	/// 0..1 fraction lost (e.g. 0.4 = "below 60% of normal").
	var/loss_fraction


// --- Subtype: germ_level ------------------------------------------------

/datum/dq_cause/germ_level
	category = "Infection"
	var/organ
	var/threshold_level


// --- Subtype: metric_threshold ------------------------------------------
//
// Watches a mob-level scalar (radiation, accumulated_rads, toxloss,
// bodytemperature, cloneloss, ...) and spawns conditions when it crosses
// thresholds. Direction matters: most metrics are "above" thresholds
// (radiation high = bad), some are "below" (bodytemperature low = bad).
//
// Each outcome can carry its own `threshold` and `tier`, just like
// organ_damage causes — so a single Acute Radiation Exposure cause can
// have Mild / Moderate / Severe outcomes at different rad levels.
//
// The condition spawns on a designated "host" organ since our
// medical_issues live on organs. Pick the organ most clinically tied
// to the metric (heart for radiation, liver for toxins, torso for
// temperature, brain for cloneloss).

/datum/dq_cause/metric_threshold
	category = "Environmental"
	/// What to read each tick. Implemented in
	/// /mob/living/carbon/human/proc/dq_get_metric().
	///   "radiation"        — acute rad value
	///   "accumulated_rads" — chronic accumulated dose
	///   "toxloss"          — current toxin damage
	///   "oxyloss"          — current oxygen-debt damage
	///   "temp_above"       — bodytemperature above normal (kelvin)
	///   "temp_below"       — drop below normal (positive number)
	///   "cloneloss"        — clone damage
	var/metric
	/// Organ tag this condition mounts on.
	var/host_organ
	/// Comparison direction: ">=" (default) or "<=".
	var/cmp = ">="


// --- Registry -----------------------------------------------------------

GLOBAL_LIST_EMPTY(dq_causes_all)
GLOBAL_LIST_EMPTY(dq_causes_by_kind)
GLOBAL_PROTECT(dq_causes_all)
GLOBAL_PROTECT(dq_causes_by_kind)

/proc/dq_causes_registry()
	if(length(GLOB.dq_causes_all))
		return GLOB.dq_causes_all
	for(var/T in subtypesof(/datum/dq_cause))
		// Abstract intermediate types (the five "kind" parent types)
		// have no authored produces; skip those naturally.
		var/datum/dq_cause/c = new T()
		if(!length(c.produces))
			qdel(c)
			continue
		GLOB.dq_causes_all += c
		// Index by the cause's PARENT type (the kind), not its own
		// concrete type. Callers look up "/datum/dq_cause/damage_event"
		// and expect every authored damage_event subtype.
		var/kind = "[parent_type_of(T)]"
		LAZYINITLIST(GLOB.dq_causes_by_kind[kind])
		GLOB.dq_causes_by_kind[kind] += c
	return GLOB.dq_causes_all

/// Walk the type tree until we hit one of the named cause "kinds"
/// (damage_event, organ_damage, severity_gate, blood_loss, germ_level).
/// Falls back to /datum/dq_cause if none matched.
/proc/parent_type_of(T)
	var/list/kinds = list(
		/datum/dq_cause/damage_event,
		/datum/dq_cause/organ_damage,
		/datum/dq_cause/severity_gate,
		/datum/dq_cause/blood_loss,
		/datum/dq_cause/germ_level,
		/datum/dq_cause/metric_threshold,
	)
	for(var/K in kinds)
		if(ispath(T, K))
			return K
	return /datum/dq_cause

/proc/dq_causes_of_kind(typepath_str)
	dq_causes_registry()
	return GLOB.dq_causes_by_kind[typepath_str] || list()

/// All causes whose produces table mentions `condition_type`. Used by
/// the book's "Caused by" lookup.
/proc/dq_causes_producing(condition_type)
	var/list/out = list()
	for(var/datum/dq_cause/c as anything in dq_causes_registry())
		for(var/datum/dq_cause_outcome/o as anything in c.produces)
			if(o.condition_type == condition_type)
				out += c
				break
	return out

/// All causes whose source is `condition_type`. Used for the book's
/// "Complications" on a condition page — only meaningful for severity_gate
/// causes (organ_damage gates aren't owned by a condition, even when a
/// condition is what damages the organ). The book combines this with
/// organ-damage targets to give a complete forward-link picture.
/proc/dq_severity_gates_from(condition_type)
	var/list/out = list()
	for(var/datum/dq_cause/severity_gate/c as anything in dq_causes_of_kind("/datum/dq_cause/severity_gate"))
		if(c.source_condition == condition_type)
			out += c
	return out
