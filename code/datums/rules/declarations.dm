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

// ---- Grilles: integrity breaking point ----

/// A grille breaks into a passable stub at its breaking point, and is fixed
/// when repaired above it. Replaces the integrity_failure crossing checks in
/// take_damage()/repair_damage() for grilles; dq_rules_settle() keeps the old
/// order (break before destruction) when one hit does both.
/datum/rule/grille_breaks
	name = "grille breaking point"
	applies_to = list(/obj/structure/grille)
	condition = list(
		REQ_ABOVE(PRED_TARGET, PROP_INTEGRITY_FAILURE, RATIO(0)),
		REQ_COMPARE(PRED_TARGET, PROP_INTEGRITY_RATIO, PRED_CMP_LTE, PRED_TARGET, PROP_INTEGRITY_FAILURE),
	)
	effect_kind = RULE_EFFECT_BEHAVIOUR
	effect_proc = /atom/proc/rule_break
	exit_proc = /atom/proc/rule_fix
	once = FALSE
	replaces = RULE_REPLACES_INTEGRITY_BREAK

/atom/proc/rule_break(datum/rule/rule)
	atom_break()

/atom/proc/rule_fix(datum/rule/rule)
	atom_fix()
