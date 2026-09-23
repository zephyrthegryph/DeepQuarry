// Declared rules (rules.md §4 examples). Each names the types it applies to;
// every generated threshold test (dq_rule_thresholds) covers them.

// ---- Heat (H3): ignition, melting, overheating, cooking, cook-off ----
// Every rule below watches the object's heat node: the object subscribes when
// it first gets a heat body (fire, an appliance, add_heat()), not at mapload.

/// Anything flammable catches fire once its own temperature reaches its
/// ignition point: its materials' lowest, else FIRE_MINIMUM_TEMPERATURE_TO_EXIST
/// for a FLAMMABLE object (paper's is a constant). Replaces /obj/fire_act's
/// "FLAMMABLE catches fire on any exposure".
/datum/rule/ignition
	name = "ignition point"
	applies_to = list(/obj)
	test_types = list(/obj/item/paper)
	condition = list(
		REQ_COMPARE(PRED_TARGET, PROP_TEMPERATURE, PRED_CMP_GTE, PRED_TARGET, PROP_IGNITION_POINT),
	)
	effect_kind = RULE_EFFECT_BEHAVIOUR
	effect_proc = /obj/proc/rule_ignite

/// Catch fire: the burning state (code/datums/components/burning.dm).
/obj/proc/rule_ignite(datum/rule/rule)
	if((resistance_flags & ON_FIRE) || !(resistance_flags & FLAMMABLE) || (resistance_flags & FIRE_PROOF))
		return
	if(HAS_TRAIT(src, TRAIT_UNDERFLOOR) || !uses_integrity)
		return
	AddComponent(/datum/component/burning, custom_fire_overlay() || GLOB.fire_overlay, burning_particles)

/// An item slumps into a molten mass at its material's melting point; what it
/// held drops out. Fire-, lava- and indestructible items are exempt.
/datum/rule/melting
	name = "melting point"
	applies_to = list(/obj/item)
	test_types = list(/obj/item/reagent_containers/glass/cooler_bottle)
	condition = list(
		REQ_COMPARE(PRED_TARGET, PROP_TEMPERATURE, PRED_CMP_GTE, PRED_TARGET, PROP_MELTING_POINT),
	)
	effect_kind = RULE_EFFECT_BEHAVIOUR
	effect_proc = /obj/item/proc/rule_melt

/obj/item/proc/rule_melt(datum/rule/rule)
	if(resistance_flags & (INDESTRUCTIBLE|LAVA_PROOF|FIRE_PROOF))
		return
	dq_rule_apply_transform(src, list(RULE_SWAP_TYPE(/obj/effect/decal/cleanable/molten_item)))

/// A structure, machine or effect above its heat limit (its materials'
/// melting point, or a per-type limit) takes a thermal damage stream until
/// it cools below it. Replaces the per-type fire_act() overrides that turned
/// an exposure temperature into damage (windows, doors, grilles, canisters,
/// exosuits, weeds, webs, shields, gargoyles).
/datum/rule/overheating
	name = "overheating"
	applies_to = list(/obj)
	excludes = list(/obj/item, /obj/machinery/door/blast, /obj/effect/hotspot)
	test_types = list(/obj/structure/window/basic)
	condition = list(
		REQ_COMPARE(PRED_TARGET, PROP_TEMPERATURE, PRED_CMP_GTE, PRED_TARGET, PROP_MELTING_POINT),
	)
	effect_kind = RULE_EFFECT_BEHAVIOUR
	effect_proc = /obj/proc/rule_overheat
	exit_proc = /obj/proc/rule_cooled
	once = FALSE

/obj/proc/rule_overheat(datum/rule/rule)
	if(resistance_flags & (INDESTRUCTIBLE|FIRE_PROOF))
		return
	AddComponent(/datum/component/overheating)

/obj/proc/rule_cooled(datum/rule/rule)
	qdel(GetComponent(/datum/component/overheating))

/// Food held at cooking temperature for long enough cooks (cook() sets the
/// raw/cooked differences). Appliances heat their contents; this rule decides.
/datum/rule/cooking
	name = "cooking"
	applies_to = list(/obj/item/reagent_containers/food/snacks)
	test_types = list(/obj/item/reagent_containers/food/snacks/meat)
	condition = list(REQ_AT_LEAST(PRED_TARGET, PROP_TEMPERATURE, KELVIN(FOOD_COOKING_TEMPERATURE)))
	effect_kind = RULE_EFFECT_BEHAVIOUR
	effect_proc = /obj/item/reagent_containers/food/snacks/proc/rule_cook
	hold_for = FOOD_COOKING_TIME

/obj/item/reagent_containers/food/snacks/proc/rule_cook(datum/rule/rule)
	if(heat_cooked)
		return
	heat_cooked = TRUE
	cook()

/// Ammunition cooks off at its cook-off temperature: it materializes (it is a
/// real object by the time its heat node exists) and detonates.
/datum/rule/cook_off
	name = "cook-off"
	applies_to = list(/obj/item/ammo_casing)
	test_types = list(/obj/item/ammo_casing/a357)
	condition = list(REQ_AT_LEAST(PRED_TARGET, PROP_TEMPERATURE, KELVIN(AMMO_COOK_OFF_TEMPERATURE)))
	effect_kind = RULE_EFFECT_BEHAVIOUR
	effect_proc = /obj/item/ammo_casing/proc/rule_cook_off

// ---- Per-type heat behaviours (each replaces a fire_act() override) ----

/// A heat behaviour at a fixed temperature: subtypes set applies_to, the
/// level (kelvin()) and the effect.
/datum/rule/heat_behaviour
	effect_kind = RULE_EFFECT_BEHAVIOUR
	abstract_type = /datum/rule/heat_behaviour

/datum/rule/heat_behaviour/New()
	if(!condition)
		condition = list(REQ_AT_LEAST(PRED_TARGET, PROP_TEMPERATURE, KELVIN(kelvin())))
	..()

/datum/rule/heat_behaviour/proc/kelvin()
	return FIRE_MINIMUM_TEMPERATURE_TO_EXIST

/datum/rule/heat_behaviour/balloon_bursts
	name = "latex balloon bursts"
	applies_to = list(/obj/item/latexballon)
	effect_proc = /obj/item/latexballon/proc/burst

/datum/rule/heat_behaviour/balloon_bursts/kelvin()
	return T0C + 100

/datum/rule/heat_behaviour/tape_ruins
	name = "tape ruins"
	applies_to = list(/obj/item/rectape)
	effect_proc = /obj/item/rectape/proc/ruin

/datum/rule/heat_behaviour/recorder_ruins_tape
	name = "tape recorder ruins its tape"
	applies_to = list(/obj/item/taperecorder)
	effect_proc = /obj/item/taperecorder/proc/rule_ruin_tape

/datum/rule/heat_behaviour/rag_ignites
	name = "rag ignites"
	applies_to = list(/obj/item/reagent_containers/glass/rag)
	effect_proc = /obj/item/reagent_containers/glass/rag/proc/rule_ignite_rag
	once = FALSE

/datum/rule/heat_behaviour/rag_ignites/kelvin()
	return T0C + 50

/datum/rule/heat_behaviour/rag_ashes
	name = "rag burns to ash"
	applies_to = list(/obj/item/reagent_containers/glass/rag)
	effect_proc = /obj/item/reagent_containers/glass/rag/proc/rule_ash

/datum/rule/heat_behaviour/rag_ashes/kelvin()
	return T0C + 900

/datum/rule/heat_behaviour/leather_dries
	name = "wet leather dries"
	applies_to = list(/obj/item/stack/wetleather)
	effect_proc = /obj/item/stack/wetleather/proc/rule_dry
	hold_for = 10 SECONDS

/datum/rule/heat_behaviour/leather_dries/kelvin()
	return 500

/datum/rule/heat_behaviour/artifact_bursts
	name = "artifact bursts"
	applies_to = list(/obj/machinery/artifact)
	effect_proc = /atom/proc/rule_delete

/datum/rule/heat_behaviour/artifact_bursts/kelvin()
	return ARTIFACT_HEAT_BREAK

/datum/rule/heat_behaviour/fueltank_explodes
	name = "fuel tank explodes"
	applies_to = list(/obj/structure/reagent_dispensers/fueltank)
	effect_proc = /obj/structure/reagent_dispensers/fueltank/proc/rule_explode

/datum/rule/heat_behaviour/fueltank_explodes/kelvin()
	return T0C + 500

/datum/rule/heat_behaviour/modded_fueltank_explodes
	name = "leaking fuel tank explodes"
	applies_to = list(/obj/structure/reagent_dispensers/fueltank)
	effect_proc = /obj/structure/reagent_dispensers/fueltank/proc/rule_modded_explode
	once = FALSE

/datum/rule/heat_behaviour/light_breaks
	name = "light breaks"
	applies_to = list(/obj/machinery/light)
	effect_proc = /obj/machinery/light/proc/rule_break_light

/datum/rule/heat_behaviour/light_breaks/kelvin()
	return T0C + 450

/datum/rule/heat_behaviour/void_core_explodes
	name = "void core explodes"
	applies_to = list(/obj/machinery/power/rtg/abductor)
	effect_proc = /obj/machinery/power/rtg/abductor/proc/rule_asplod

/datum/rule/heat_behaviour/kugelblitz_explodes
	name = "kugelblitz explodes"
	applies_to = list(/obj/machinery/power/rtg/kugelblitz)
	effect_proc = /obj/machinery/power/rtg/kugelblitz/proc/rule_asplod

/datum/rule/heat_behaviour/fire_alarm
	name = "fire alarm trips"
	applies_to = list(/obj/machinery/firealarm)
	effect_proc = /obj/machinery/firealarm/proc/rule_heat_alarm
	once = FALSE

/datum/rule/heat_behaviour/fire_alarm/kelvin()
	return T0C + 200

/datum/rule/heat_behaviour/foam_dissolves
	name = "foam dissolves"
	applies_to = list(/obj/effect/effect/foam)
	effect_proc = /obj/effect/effect/foam/proc/rule_dissolve

/datum/rule/heat_behaviour/foam_dissolves/kelvin()
	return 525

/datum/rule/heat_behaviour/bonfire_lights
	name = "bonfire lights"
	applies_to = list(/obj/structure/bonfire)
	effect_proc = /obj/structure/bonfire/proc/rule_light
	once = FALSE

/datum/rule/heat_behaviour/fireplace_lights
	name = "fireplace lights"
	applies_to = list(/obj/structure/fireplace)
	effect_proc = /obj/structure/fireplace/proc/rule_light
	once = FALSE

/datum/rule/heat_behaviour/phoron_airlock_burns
	name = "phoron airlock burns"
	applies_to = list(/obj/machinery/door/airlock/phoron)
	effect_proc = /obj/machinery/door/airlock/phoron/proc/rule_burn

/datum/rule/heat_behaviour/material_door_burns
	name = "material door burns"
	applies_to = list(/obj/structure/simple_door)
	effect_proc = /obj/structure/simple_door/proc/rule_burn
	once = FALSE

/datum/rule/heat_behaviour/weaversilk_burns
	name = "weaver silk burns away"
	applies_to = list(/obj/effect/weaversilk)
	effect_proc = /obj/effect/weaversilk/proc/rule_burn_away

/atom/proc/rule_delete(datum/rule/rule)
	qdel(src)

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
