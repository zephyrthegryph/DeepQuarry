// Substance refining via the Particle Accelerator (reachable through existing machines).
//
// Refining isn't a standalone bench: you bombard a loaded substance stack in a particle
// smasher (the PA's beam target) until it builds enough energy to force the trade. Load a
// substance sheet into the smasher, click it to pick which axis to push (the same trades
// the bench offered), then fire the PA at it — when it charges past the threshold, the
// sheet recasts as the refined alloy. The smasher already accepts /obj/item/stack/material
// (substance stacks included) and already accumulates `energy` from the PA beam, so this
// only adds the substance branch; non-substance targets keep their recipe behaviour.

/// Energy (of the smasher's max_energy 600) a substance must reach before the refine fires.
#define SUBSTANCE_REFINE_ENERGY 300

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
	var/amount = target.amount
	var/turf/T = get_turf(src)
	QDEL_NULL(target)
	substance_spawn_stack(T, refined, amount)
	qdel(refined)
	energy = max(0, energy - SUBSTANCE_REFINE_ENERGY)
	successful_craft = FALSE
	visible_message(span_notice("\The [src] discharges, recasting the stock as a refined alloy."))
	update_icon()
