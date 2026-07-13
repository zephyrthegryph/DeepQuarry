// Substance combining via the fusion reactor ("R-UST", reachable through existing machines).
//
// Alloying isn't a standalone combiner: you feed two substance stacks into the R-UST
// Tokamak core's reactant slots and let the live field fuse them. While the field is hot,
// the core periodically consumes a sheet from each, runs the same substance_combine resolver
// the bench used, casts the resulting alloy (+ byproducts) at the core, and turns the
// reaction's magnitude into reactor energy. A clean, high-yield fuse stabilises the field
// (AddEnergy bleeds instability); a hazardous one destabilises it toward a breach — so the
// danger of a volatile mix lands as reactor instability, the reactor's own failure model.
//
// The two-slot load + resolver plumbing mirrors substance_combiner/do_combine; the only
// new coupling is to the field's AddEnergy() (power) and tick_instability (hazard).

/// Minimum delay between fuses while the field runs (one sheet-pair per interval).
#define FUSION_COMBINE_INTERVAL (5 SECONDS)

/obj/machinery/power/fusion_core
	/// The two loaded substance reactant stacks (consumed a sheet at a time while fusing).
	var/obj/item/stack/material/substance/fuse_a
	var/obj/item/stack/material/substance/fuse_b
	/// world.time the next fuse is allowed.
	var/next_fusion_combine = 0

// Build the resolver context from the running reactor: the field strength is the
// containment ceiling (engineering), and the volatility is the room's ambient atmos
// PLUS the reactor's own plasma heat on top (fusing hot is dangerous). Sharing
// substance_env_context() means the reactor room's temperature/pressure shift the
// fuse exactly as they shift the bench combiner.
/obj/machinery/power/fusion_core/proc/fusion_substance_context()
	var/energy_ceiling = clamp(round(field_strength / 5), 20, 200)
	var/plasma_heat = owned_field ? clamp(round(owned_field.plasma_temperature / 1000), 0, 40) : 0
	return substance_env_context(src, energy_ceiling, plasma_heat)

// Called from fusion_core/process() while the field is live: if both reactant slots hold a
// substance and the interval has elapsed, fuse one sheet from each into the combined alloy.
/obj/machinery/power/fusion_core/proc/try_fusion_combine()
	if(!owned_field || world.time < next_fusion_combine)
		return
	var/datum/substance/A = substance_stack_substance(fuse_a)
	var/datum/substance/B = substance_stack_substance(fuse_b)
	if(!A || !B)
		return
	next_fusion_combine = world.time + FUSION_COMBINE_INTERVAL

	var/datum/substance_reaction/R = substance_combine(A, B, fusion_substance_context())
	if(!R)
		return
	substance_record_observation(A, B, R)

	var/turf/T = get_turf(src)
	if(R.output)
		substance_spawn_stack(T, R.output, R.output.quantity)
	for(var/datum/substance/bp in R.byproducts)
		substance_spawn_stack(T, bp, bp.quantity)

	// Fusion yield: magnitude becomes reactor energy/heat (AddEnergy also bleeds instability,
	// so a clean high-yield fuse self-stabilises). A hazard instead drives the field unstable.
	owned_field.AddEnergy(R.magnitude * 100, R.magnitude * 10)
	if(R.hazard)
		owned_field.tick_instability += R.hazard.severity * 0.5
		visible_message(span_danger("\The [src] lurches as the reaction destabilises the field!"))

	consume_fuse_sheet(TRUE)
	consume_fuse_sheet(FALSE)
	qdel(R)
	use_power(active_power_usage)

/obj/machinery/power/fusion_core/proc/consume_fuse_sheet(first)
	var/obj/item/stack/material/substance/stack = first ? fuse_a : fuse_b
	if(!stack)
		return
	stack.use(1)
	if(QDELETED(stack) || stack.amount <= 0)
		if(first)
			fuse_a = null
		else
			fuse_b = null

// Try to load a substance stack into a free reactant slot. Returns TRUE if handled.
/obj/machinery/power/fusion_core/proc/load_fuse_substance(obj/item/stack/material/substance/stack, mob/user)
	if(!substance_stack_substance(stack))
		to_chat(user, span_warning("\The [stack] is not a workable substance."))
		return TRUE
	if(fuse_a && fuse_b)
		to_chat(user, span_warning("Both reactant slots are loaded."))
		return TRUE
	if(!user.unEquip(stack, src))
		return TRUE
	if(!fuse_a)
		fuse_a = stack
	else
		fuse_b = stack
	to_chat(user, span_notice("You feed \the [stack] into \the [src]'s reactant slots."))
	return TRUE

/obj/machinery/power/fusion_core/proc/drop_fuse_slots()
	var/turf/T = get_turf(src)
	if(fuse_a)
		fuse_a.forceMove(T)
		fuse_a = null
	if(fuse_b)
		fuse_b.forceMove(T)
		fuse_b = null

/obj/machinery/power/fusion_core/verb/eject_reactant_substances()
	set src in view(1)
	set name = "Eject Reactant Substances"
	set category = "Object"
	if(usr.incapacitated() || !Adjacent(usr))
		return
	if(!fuse_a && !fuse_b)
		to_chat(usr, span_notice("\The [src] has no loaded reactant substances."))
		return
	drop_fuse_slots()
	to_chat(usr, span_notice("You unload \the [src]'s reactant substances."))
