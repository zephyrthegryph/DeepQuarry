// Substance refining via the Particle Accelerator (reachable through existing machines).
//
// Refining isn't a standalone bench: you bombard a loaded substance stack in a particle
// smasher (the PA's beam target) until it builds enough energy to force the trade. Load a
// substance sheet into the smasher, click it to pick which axis to push (the same trades
// the bench offered), then fire the PA at it — when it charges past the threshold, the
// sheet recasts as the refined alloy. The smasher already accepts /obj/item/stack/material
// (substance stacks included) and already accumulates `energy` from the PA beam, so this
// only adds the substance branch; non-substance targets keep their recipe behaviour.

GLOBAL_LIST_INIT(substance_refine_ops, list(
	"Concentrate — Energy up, Volatility up, Purity down",
	"Stabilize — Volatility down, Energy down",
	"Bond — Affinity up, Energy down",
	"Purify — Purity up, Energy down",
	"Tune resonance + (Purity down)",
	"Tune resonance − (Purity down)",
))

/proc/apply_refine(datum/substance/substance, choice, datum/substance_context/context = null)
	switch(choice)
		if("Concentrate — Energy up, Volatility up, Purity down")
			substance.energy = clamp(substance.energy + 15, 0, SUBSTANCE_ATTR_MAX)
			substance.volatility = clamp(substance.volatility + 10, 0, SUBSTANCE_ATTR_MAX)
			substance.purity = clamp(substance.purity - 10, 0, SUBSTANCE_ATTR_MAX)
		if("Stabilize — Volatility down, Energy down")
			substance.volatility = clamp(substance.volatility - 15, 0, SUBSTANCE_ATTR_MAX)
			substance.energy = clamp(substance.energy - 8, 0, SUBSTANCE_ATTR_MAX)
		if("Bond — Affinity up, Energy down")
			substance.affinity = clamp(substance.affinity + 15, 0, SUBSTANCE_ATTR_MAX)
			substance.energy = clamp(substance.energy - 6, 0, SUBSTANCE_ATTR_MAX)
		if("Purify — Purity up, Energy down")
			substance.purity = clamp(substance.purity + 15, 0, SUBSTANCE_ATTR_MAX)
			substance.energy = clamp(substance.energy - 10, 0, SUBSTANCE_ATTR_MAX)
		if("Tune resonance + (Purity down)")
			substance.resonance = (substance.resonance + 30) % SUBSTANCE_RES_MAX
			substance.purity = clamp(substance.purity - 8, 0, SUBSTANCE_ATTR_MAX)
		if("Tune resonance − (Purity down)")
			substance.resonance = (substance.resonance - 30 + SUBSTANCE_RES_MAX) % SUBSTANCE_RES_MAX
			substance.purity = clamp(substance.purity - 8, 0, SUBSTANCE_ATTR_MAX)
	if(!context)
		return
	if(context.energy_ceiling && substance.energy > context.energy_ceiling)
		var/overdrive = substance.energy - context.energy_ceiling
		substance.energy = context.energy_ceiling
		substance.volatility = clamp(substance.volatility + round(overdrive / 2), 0, SUBSTANCE_ATTR_MAX)
	if(context.volatility_mod)
		substance.volatility = clamp(substance.volatility + round(context.volatility_mod / 3), 0, SUBSTANCE_ATTR_MAX)

/// Energy (of the smasher's max_energy 600) a substance must reach before the refine fires.
#define SUBSTANCE_REFINE_ENERGY 300

/// Existing biological and archaeological items that the particle focus can
/// destructively render. This keeps acquisition in physical machines and leaves
/// ordinary slime chemistry, botany grinding, and anomaly devices intact as
/// competing uses for the same finite source.
/proc/substance_source_category(obj/item/source)
	if(istype(source, /obj/item/slime_extract))
		return "bio"
	if(istype(source, /obj/item/reagent_containers/food/snacks/grown))
		return "botany"
	if(istype(source, /obj/item/anobattery))
		return "field"
	return null

/proc/substance_family_from_artifact_effect(effect_type)
	switch(effect_type)
		if(EFFECT_ELECTIC_FIELD, EFFECT_EMP, EFFECT_CELL, EFFECT_GENERATOR)
			return SUBFAM_DISCHARGE
		if(EFFECT_TEMPERATURE)
			return SUBFAM_THERMAL
		if(EFFECT_GRAVIATIONAL_WAVES, EFFECT_POLTERGEIST, EFFECT_ANIMATE, EFFECT_BERSERK)
			return SUBFAM_FORCE
		if(EFFECT_FORCEFIELD)
			return SUBFAM_FIELD
		if(EFFECT_GAIA, EFFECT_RESURRECT, EFFECT_VAMPIRE, EFFECT_HEALTH, EFFECT_ROBOT_HEALTH)
			return SUBFAM_SPORE
		if(EFFECT_RADIATE)
			return SUBFAM_RADIANT
		if(EFFECT_TELEPORT, EFFECT_FEYSIGHT)
			return SUBFAM_VOID
		if(EFFECT_GAS, EFFECT_DNASWITCH)
			return SUBFAM_CORROSIVE
	return SUBFAM_FIELD

/obj/machinery/particle_smasher/proc/try_substance_source_render()
	if(energy < SUBSTANCE_REFINE_ENERGY || !target)
		return FALSE
	var/category = substance_source_category(target)
	if(!category)
		return FALSE
	var/datum/substance/rendered
	var/output_amount = 1
	if(category == "field")
		var/obj/item/anobattery/battery = target
		if(!battery.battery_effect)
			visible_message(span_warning("The particle field rejects [battery]; it contains no harvested anomaly signature."))
			energy = max(0, energy - 50)
			return FALSE
		rendered = new
		rendered.name = "[substance_family_name(substance_family_from_artifact_effect(battery.battery_effect.effect_type))] anomaly condensate"
		rendered.family = substance_family_from_artifact_effect(battery.battery_effect.effect_type)
		rendered.trigger = substance_family_default_trigger(rendered.family)
		var/charge_fraction = clamp(battery.stored_charge / max(battery.capacity, 1), 0, 1)
		rendered.energy = clamp(round(55 + charge_fraction * 40), 0, SUBSTANCE_ATTR_MAX)
		rendered.volatility = rand(45, 90)
		rendered.affinity = rand(20, 60)
		rendered.purity = rand(25, 70)
		rendered.resonance = rand(0, SUBSTANCE_RES_MAX - 1)
		output_amount = clamp(2 + round(battery.capacity / 1500), 2, 7)
	else
		var/list/source_ids = substance_archetype_ids_by_category(category)
		if(!length(source_ids))
			return FALSE
		output_amount = category == "bio" ? 3 : 2
		if(category == "bio")
			var/obj/item/slime_extract/extract = target
			output_amount = clamp(2 + extract.uses, 2, 6)
		else
			var/obj/item/reagent_containers/food/snacks/grown/produce = target
			output_amount = clamp(2 + round(max(produce.potency, 0) / 30), 2, 6)
		rendered = substance_from_archetype(pick(source_ids), output_amount)
	if(!rendered)
		return FALSE
	var/turf/output_turf = get_turf(src)
	if(!output_turf)
		qdel(rendered)
		return FALSE
	var/source_name = target.name
	var/obj/item/stack/material/substance/output = substance_spawn_stack(output_turf, rendered, output_amount)
	var/rendered_name = rendered.name
	qdel(rendered)
	if(!output || QDELETED(output))
		return FALSE
	// Do not destroy the finite source until its replacement exists. Registration or
	// material creation failures therefore leave the player's input recoverable.
	var/obj/item/consumed_source = src.target
	src.target = null
	qdel(consumed_source)
	energy = max(0, energy - SUBSTANCE_REFINE_ENERGY)
	successful_craft = FALSE
	src.target = null
	visible_message(span_notice("The focused beam strips [source_name] into [output_amount] sheets of [rendered_name], leaving no unprocessed source behind."))
	update_icon()
	return output

/obj/machinery/particle_smasher
	/// The refinement to force on a loaded substance once charged (a GLOB.substance_refine_ops entry).
	var/substance_refine_op

// Clicking a smasher holding a substance lets the operator choose the refinement that will
// be forced once it charges. Falls through to default behaviour for anything else.
/obj/machinery/particle_smasher/attack_hand(mob/user)
	if(istype(target, /obj/item/stack/material/substance) && substance_stack_substance(target))
		var/choice = input(user, "Set the refinement to force once charged.", "Particle Refinement", substance_refine_op) as null|anything in GLOB.substance_refine_ops
		if(isnull(choice) || !Adjacent(user))
			return TRUE
		substance_refine_op = choice
		to_chat(user, span_notice("\The [src] is set to <b>[choice]</b>. Bombard the stock to force the trade."))
		return TRUE
	return ..()

// Called from the smasher's process(): once a loaded substance stack has charged past the
// threshold and an op is chosen, recast it as the refined alloy and vent the charge.
/obj/machinery/particle_smasher/proc/try_substance_refine()
	if(energy < SUBSTANCE_REFINE_ENERGY)
		return
	var/datum/substance/S = substance_stack_substance(target)
	if(!S || !substance_refine_op)
		return
	// Engineering axis: how hard the accelerator charged sets the refine's energy ceiling
	// (fully charged = cleanest). Atmos axis: the smasher room's ambient reading.
	var/energy_ceiling = clamp(round((energy / max_energy) * SUBSTANCE_ATTR_MAX), 40, SUBSTANCE_ATTR_MAX)
	var/datum/substance/refined = S.Clone()
	apply_refine(refined, substance_refine_op, substance_env_context(src, energy_ceiling))
	var/obj/item/stack/material/substance/substance_target = target
	var/amount = substance_target.amount
	var/turf/T = get_turf(src)
	QDEL_NULL(target)
	substance_spawn_stack(T, refined, amount)
	qdel(refined)
	energy = max(0, energy - SUBSTANCE_REFINE_ENERGY)
	successful_craft = FALSE
	visible_message(span_notice("\The [src] discharges, recasting the stock as a refined alloy."))
	update_icon()
