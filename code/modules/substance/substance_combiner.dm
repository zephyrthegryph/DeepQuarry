// The substance combiner (alloying station).
//
// The considered combination mode: ALLOYING — fuse two substances into one new
// substance carrying the derived effect and a fresh attribute profile. It operates
// on substance MATERIAL stacks (a substance is always material, never a vial):
// load two stacks, combine, and it consumes a sheet from each and casts a sheet of
// the result (+ any byproduct sheets), detonating any hazard on its own tile — so
// the danger lands on the crew that pushed the mix.

/obj/machinery/substance_combiner
	name = "substance combiner"
	desc = "A reinforced alloying chamber. Load two substance material stacks and combine. Pushing a volatile mix here is how accidents happen."
	icon = 'icons/obj/chemical.dmi'
	icon_state = "mixer0"
	density = TRUE
	anchored = TRUE
	use_power = USE_POWER_IDLE
	idle_power_usage = 20
	active_power_usage = 200
	/// The two loaded input stacks.
	var/obj/item/stack/material/substance/slot_a
	var/obj/item/stack/material/substance/slot_b
	/// A short text record of the last combination, for the UI.
	var/list/last_result
	/// Engineering's axis: the safe magnitude this rig can contain. Exceed it and
	/// containment fails. A sturdier/upgraded chamber raises the ceiling.
	var/energy_ceiling = 75

/obj/machinery/substance_combiner/Destroy()
	QDEL_NULL(slot_a)
	QDEL_NULL(slot_b)
	last_result = null
	return ..()

/obj/machinery/substance_combiner/attackby(obj/item/I, mob/user)
	if(istype(I, /obj/item/stack/material/substance))
		var/obj/item/stack/material/substance/stack = I
		if(!substance_stack_substance(stack))
			to_chat(user, span_warning("\The [stack] is not a workable substance."))
			return
		if(slot_a && slot_b)
			to_chat(user, span_warning("Both input slots are full."))
			return
		if(!user.unEquip(stack, src))
			return
		if(!slot_a)
			slot_a = stack
		else
			slot_b = stack
		to_chat(user, span_notice("You load \the [stack] into \the [src]."))
		update_icon()
		return
	return ..()

/obj/machinery/substance_combiner/attack_hand(mob/user)
	if(..())
		return
	if(stat & (BROKEN|NOPOWER))
		return
	tgui_interact(user)

/obj/machinery/substance_combiner/tgui_interact(mob/user, datum/tgui/ui)
	ui = SStgui.try_update_ui(user, src, ui)
	if(!ui)
		ui = new(user, src, "SubstanceCombiner", name)
		ui.open()

/obj/machinery/substance_combiner/tgui_data(mob/user, datum/tgui/ui, datum/tgui_state/state)
	var/list/data = list()
	data["slot_a"] = stack_data(slot_a)
	data["slot_b"] = stack_data(slot_b)
	data["can_combine"] = (substance_stack_substance(slot_a) && substance_stack_substance(slot_b)) ? TRUE : FALSE
	data["last_result"] = last_result
	data["knowledge"] = substance_knowledge_summary()
	data["rig"] = list(
		"ceiling" = energy_ceiling,
		"volatility_mod" = ambient_volatility_mod(),
		"ambient" = ambient_readout(),
	)
	return data

// Build the resolver context from this rig's surroundings (atmospherics' axis) and
// its containment rating (engineering's axis). Both are shared with the
// particle-accelerator and fusion-core substance paths (substance_resolver.dm).
/obj/machinery/substance_combiner/proc/build_context()
	return substance_env_context(src, energy_ceiling)

/obj/machinery/substance_combiner/proc/ambient_volatility_mod()
	return substance_ambient_volatility_mod(src)

/obj/machinery/substance_combiner/proc/ambient_readout()
	return substance_ambient_readout(src)

/obj/machinery/substance_combiner/proc/stack_data(obj/item/stack/material/substance/stack)
	var/datum/substance/S = substance_stack_substance(stack)
	if(!S)
		return null
	return list(
		"name" = stack.material ? stack.material.display_name : S.name,
		"family" = substance_family_name(S.family),
		"trigger" = substance_trigger_name(S.trigger),
		"amount" = stack.amount,
	)

/obj/machinery/substance_combiner/tgui_act(action, list/params, datum/tgui/ui, datum/tgui_state/state)
	if(..())
		return TRUE
	switch(action)
		if("combine")
			do_combine(usr)
			return TRUE
		if("eject_a")
			eject_slot(usr, TRUE)
			return TRUE
		if("eject_b")
			eject_slot(usr, FALSE)
			return TRUE
	return FALSE

/obj/machinery/substance_combiner/proc/eject_slot(mob/user, first)
	var/obj/item/stack/material/substance/stack = first ? slot_a : slot_b
	if(!stack)
		return
	stack.forceMove(get_turf(src))
	if(user && Adjacent(user))
		user.put_in_hands(stack)
	if(first)
		slot_a = null
	else
		slot_b = null
	update_icon()

/obj/machinery/substance_combiner/proc/do_combine(mob/user)
	var/datum/substance/A = substance_stack_substance(slot_a)
	var/datum/substance/B = substance_stack_substance(slot_b)
	if(!A || !B)
		to_chat(user, span_warning("Load two substance stacks first."))
		return
	if(stat & (BROKEN|NOPOWER))
		return

	var/datum/substance_reaction/R = substance_combine(A, B, build_context())
	if(!R)
		to_chat(user, span_warning("\The [src] fails to initiate a reaction."))
		return

	// Log what this combination revealed about its inputs (inference, never a scan).
	substance_record_observation(A, B, R)

	var/turf/T = get_turf(src)

	// Cast the output as its own stack (if the bond held).
	if(R.output)
		substance_spawn_stack(T, R.output, R.output.quantity)
	else
		visible_message(span_warning("\The [src] vents a useless sludge — nothing bonded."))

	// Cast byproducts as their own stacks.
	for(var/datum/substance/bp in R.byproducts)
		substance_spawn_stack(T, bp, bp.quantity)

	// Hazard erupts on the machine's tile.
	if(R.hazard)
		substance_hazard_detonate(T, R.hazard)

	// Record a compact result for the UI.
	last_result = list(
		"relationship" = substance_relationship_name(R.relationship),
		"magnitude" = R.magnitude,
		"control" = R.control,
		"purity" = R.purity,
		"hazard" = R.hazard ? R.hazard.desc : null,
	)

	// Consume one sheet from each input; clear a slot whose stack is used up.
	consume_sheet(TRUE)
	consume_sheet(FALSE)
	qdel(R)
	update_icon()
	use_power(active_power_usage)

/obj/machinery/substance_combiner/proc/consume_sheet(first)
	var/obj/item/stack/material/substance/stack = first ? slot_a : slot_b
	if(!stack)
		return
	stack.use(1)
	if(QDELETED(stack) || stack.amount <= 0)
		if(first)
			slot_a = null
		else
			slot_b = null

/obj/machinery/substance_combiner/update_icon()
	icon_state = (slot_a || slot_b) ? "mixer1" : "mixer0"
