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
	applies_to = list(/obj/item, /obj/structure, /obj/machinery, /obj/vehicle, /obj/effect/alien, /obj/effect/spider)
	// The generic rule-test fixture is a bare property target, not a real
	// flammable item; it carries its own test_only rules instead.
	excludes = list(/obj/item/dq_rule_test)
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
	excludes = list(/obj/item/dq_rule_test)
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
	applies_to = list(/obj/structure, /obj/machinery, /obj/mecha, /obj/vehicle, /obj/effect/alien/weeds, /obj/effect/spider, /obj/effect/shield)
	excludes = list(/obj/machinery/door/blast)
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
	// explode()'s explosion() has a real blast radius reaching neighbouring
	// tiles, which can damage whatever a later generated case places on the
	// shared test floor.
	skip_generated_test = TRUE

/datum/rule/heat_behaviour/fueltank_explodes/kelvin()
	return T0C + 500

/datum/rule/heat_behaviour/modded_fueltank_explodes
	name = "leaking fuel tank explodes"
	applies_to = list(/obj/structure/reagent_dispensers/fueltank)
	effect_proc = /obj/structure/reagent_dispensers/fueltank/proc/rule_modded_explode
	once = FALSE
	skip_generated_test = TRUE

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
	// asplod() schedules a real explosion() on a 10-second delayed timer, well
	// outside the generated test's own case: it detonates on whatever shares
	// the test's floor turf several unrelated cases later.
	skip_generated_test = TRUE

/datum/rule/heat_behaviour/kugelblitz_explodes
	name = "kugelblitz explodes"
	applies_to = list(/obj/machinery/power/rtg/kugelblitz)
	effect_proc = /obj/machinery/power/rtg/kugelblitz/proc/rule_asplod
	// asplod() spawns a persistent /obj/singularity on the test floor, which
	// keeps eating whatever later cases place there.
	skip_generated_test = TRUE

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
