// Declared rules (rules.md §4 examples). Each names the types it applies to;
// every generated threshold test (dq_rule_thresholds) covers them.

// ---- Paper: ignition point ----

/// Paper catches fire once its own temperature reaches its ignition point.
/// Replaces /obj/fire_act's "FLAMMABLE catches fire on any exposure" for paper:
/// a fire exposure now heats the paper's node, and the rule decides. Same
/// result for any exposure at or above the ignition point (hotspots start at
/// FIRE_MINIMUM_TEMPERATURE_TO_EXIST, so cooler exposures no longer ignite it).
/datum/rule/paper_ignition
	name = "paper ignition"
	applies_to = list(/obj/item/paper)
	condition = list(
		REQ_COMPARE(PRED_TARGET, PROP_TEMPERATURE, PRED_CMP_GTE, PRED_TARGET, PROP_IGNITION_POINT),
	)
	effect_kind = RULE_EFFECT_BEHAVIOUR
	effect_proc = /obj/proc/rule_ignite
	replaces = RULE_REPLACES_IGNITION

/// Catch fire the way fire_act() does. Behaviour effect for ignition rules.
/obj/proc/rule_ignite(datum/rule/rule)
	if((resistance_flags & ON_FIRE) || !(resistance_flags & FLAMMABLE) || (resistance_flags & FIRE_PROOF))
		return
	if(HAS_TRAIT(src, TRAIT_UNDERFLOOR))
		return
	AddComponent(/datum/component/burning, custom_fire_overlay() || GLOB.fire_overlay, burning_particles)

// ---- Plastic: melting point ----

/// A plastic water-cooler bottle slumps into a molten mass at its material's
/// melting point (data transform: swap the type; contents drop out).
/datum/rule/plastic_bottle_melts
	name = "plastic melts"
	applies_to = list(/obj/item/reagent_containers/glass/cooler_bottle)
	condition = list(
		REQ_COMPARE(PRED_TARGET, PROP_TEMPERATURE, PRED_CMP_GTE, PRED_TARGET, PROP_MELTING_POINT),
	)
	effect_kind = RULE_EFFECT_DATA
	transform = list(RULE_SWAP_TYPE(/obj/effect/decal/cleanable/molten_item))

// ---- Integrity breakpoints (damage.md §6) ----
//
// Every type's damage breakpoints are rules, declared once here:
//   damaged at 3/4, 1/2, 1/4   generated flavour text (damage_flavour_text())
//   broken at integrity_failure atom_break() / atom_fix()
//   destroyed at 0              atom_destruction()
// Rules run in declaration order, so when one hit crosses several levels the
// break still runs before the destruction, as the old take_damage() did.
// Only types that declare a breakpoint (integrity_failure > 0) or have damage
// flavour get the rules, so plain items and structures cost nothing.

/// Types whose examine text shows their damage band.
#define DAMAGE_FLAVOUR_TYPES list( 	/obj/structure/window, 	/obj/structure/railing, 	/obj/structure/low_wall, 	/obj/structure/table, 	/obj/machinery/door, 	/obj/structure/expedition_demo_target, )

/// The object breaks at its breaking point, and is fixed when repaired above
/// it. Replaces the integrity_failure crossing checks in take_damage() and
/// repair_damage().
/datum/rule/integrity_breaks
	name = "breaking point"
	applies_to = list(/obj)
	condition = list(
		REQ_ABOVE(PRED_TARGET, PROP_INTEGRITY_FAILURE, RATIO(0)),
		REQ_COMPARE(PRED_TARGET, PROP_INTEGRITY_RATIO, PRED_CMP_LTE, PRED_TARGET, PROP_INTEGRITY_FAILURE),
	)
	effect_kind = RULE_EFFECT_BEHAVIOUR
	effect_proc = /atom/proc/rule_break
	exit_proc = /atom/proc/rule_fix
	once = FALSE
	replaces = RULE_REPLACES_INTEGRITY_BREAK

/datum/rule/integrity_breaks/applies_to_type(path)
	var/atom/A = path
	return initial(A.uses_integrity) && initial(A.integrity_failure) > 0 && initial(A.max_integrity) > 0

/// Damage flavour: one rule per band. Each sets damage_band while it holds.
/datum/rule/damage_flavour
	name = "damage flavour"
	abstract_type = /datum/rule/damage_flavour
	applies_to = DAMAGE_FLAVOUR_TYPES
	effect_kind = RULE_EFFECT_BEHAVIOUR
	effect_proc = /atom/proc/rule_enter_damage_band
	exit_proc = /atom/proc/rule_leave_damage_band
	once = FALSE

/datum/rule/damage_flavour/applies_to_type(path)
	var/atom/A = path
	return initial(A.uses_integrity) && initial(A.max_integrity) > 0

/datum/rule/damage_flavour/light
	name = "damaged below 3/4"
	band = DAMAGE_BAND_LIGHT
	condition = list(REQ_BELOW(PRED_TARGET, PROP_INTEGRITY_RATIO, RATIO(0.75)))

/datum/rule/damage_flavour/moderate
	name = "damaged below 1/2"
	band = DAMAGE_BAND_MODERATE
	condition = list(REQ_BELOW(PRED_TARGET, PROP_INTEGRITY_RATIO, RATIO(0.5)))

/datum/rule/damage_flavour/heavy
	name = "damaged below 1/4"
	band = DAMAGE_BAND_HEAVY
	condition = list(REQ_BELOW(PRED_TARGET, PROP_INTEGRITY_RATIO, RATIO(0.25)))

/// Destroyed at zero integrity. Declared after the break so one hit that does
/// both breaks first.
/datum/rule/integrity_destroyed
	name = "destroyed"
	applies_to = list(/obj)
	condition = list(REQ_AT_MOST(PRED_TARGET, PROP_INTEGRITY_RATIO, RATIO(0)))
	effect_kind = RULE_EFFECT_BEHAVIOUR
	effect_proc = /atom/proc/rule_destroy
	// Repaired from zero (a survivor of atom_destruction), it re-arms.
	once = FALSE
	replaces = RULE_REPLACES_INTEGRITY_DESTRUCTION

/datum/rule/integrity_destroyed/applies_to_type(path)
	var/atom/A = path
	if(!initial(A.uses_integrity) || initial(A.max_integrity) <= 0)
		return FALSE
	if(initial(A.integrity_failure) > 0)
		return TRUE
	for(var/root in DAMAGE_FLAVOUR_TYPES)
		if(ispath(path, root))
			return TRUE
	return FALSE

#undef DAMAGE_FLAVOUR_TYPES

/atom/proc/rule_break(datum/rule/rule)
	atom_break(last_damage_flag)

/atom/proc/rule_fix(datum/rule/rule)
	atom_fix()

/atom/proc/rule_destroy(datum/rule/rule)
	atom_destruction(last_damage_flag)

/atom/proc/rule_enter_damage_band(datum/rule/rule)
	damage_band = max(damage_band, rule.band)

/atom/proc/rule_leave_damage_band(datum/rule/rule)
	if(damage_band >= rule.band)
		damage_band = rule.band - 1
