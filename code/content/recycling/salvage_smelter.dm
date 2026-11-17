/**
 * Cargo's salvage smelter: melts scrap, junk and unwanted freight straight into material sheets, from what each thing is
 * recorded as made of (its composition, as the recycling crusher reads it, with alloys broken into their parts).
 *
 * Conservation: it returns at most `efficiency` (< 1) of what a thing is made of, so nothing it smelts returns more than
 * it cost to make (code/tests/unit_tests/dq_fab_conservation_tests.dm proves compositions never exceed costs). It keeps
 * partial sheets in its melt and never rounds up. It refuses material sheets, which are already processed.
 */
/obj/machinery/recycling/salvage_smelter
	name = "salvage smelter"
	desc = "A Cargo-grade induction smelter that melts salvage down to sheets of whatever it was made of. It keeps partial sheets in its melt until there is enough for a whole one."
	icon = 'icons/obj/machines/mining_machines.dmi'
	icon_state = "furnace"
	anchored = FALSE
	/// The share of a thing's materials it recovers.
	var/efficiency = SALVAGE_SMELTER_EFFICIENCY
	/// Material name -> units melted and not yet poured into a sheet.
	var/list/salvage_melt

/obj/machinery/recycling/salvage_smelter/recycle_refusal(obj/item/O)
	if(istype(O, /obj/item/stack/material))
		return /datum/msg/recycling/wrong_input
	if(!length(salvage_composition(O)))
		return /datum/msg/recycling/wrong_input
	return ..()

/// A conveyed thing it can't smelt goes out the far side, so a salvage line doesn't jam.
/obj/machinery/recycling/salvage_smelter/divert_item(obj/item/O)
	if(!ishuman(O.loc))
		O.forceMove(get_step(src, turn(dir, 180)))

/obj/machinery/recycling/salvage_smelter/take_item(obj/item/O)
	. = ..()
	set_working(TRUE)
	set_use_power(USE_POWER_ACTIVE)
	after(src, 4 SECONDS, PROC_REF(smelt_done), with = list(O))

/// What smelting `O` and everything in it would melt down to, before efficiency: material name -> units.
/obj/machinery/recycling/salvage_smelter/proc/salvage_composition(obj/item/O)
	. = list()
	for(var/obj/item/part as anything in O.get_all_contents_type(/obj/item))
		var/units = breakdown_units(part)
		var/list/composition = part.get_material_composition()
		for(var/datum/material/M as anything in composition)
			if(composition[M] > 0)
				.[M.name] += composition[M] * units

/obj/machinery/recycling/salvage_smelter/proc/smelt_done(obj/item/O)
	smelt(O)
	set_use_power(USE_POWER_IDLE)
	set_working(FALSE)

/// Melt `O` into the melt and pour every whole sheet. Returns the sheets poured, material name -> count.
/obj/machinery/recycling/salvage_smelter/proc/smelt(obj/item/O)
	var/list/composition = salvage_composition(O)
	for(var/material_name in composition)
		LAZYINITLIST(salvage_melt)
		salvage_melt[material_name] += composition[material_name] * efficiency
	if(GLOB.fab_trace)
		log_world("FAB: [src] smelted [O]: [json_encode(composition)] at [efficiency]; melt now [json_encode(salvage_melt)]")
	consumed(O, src)
	return pour_sheets()

/// Pour whole sheets from the melt onto the turf in front; partial sheets stay in the melt.
/obj/machinery/recycling/salvage_smelter/proc/pour_sheets()
	. = list()
	var/turf/T = get_step(src, dir)
	for(var/material_name in salvage_melt)
		var/datum/material/M = get_material_by_name(material_name)
		if(!M?.stack_type)
			continue
		var/sheets = round(salvage_melt[material_name] / SHEET_MATERIAL_AMOUNT)
		if(sheets <= 0)
			continue
		salvage_melt[material_name] -= sheets * SHEET_MATERIAL_AMOUNT
		.[material_name] = sheets
		var/obj/item/stack/stack_type = M.stack_type
		var/max_amount = initial(stack_type.max_amount) || 50
		while(sheets > 0)
			var/batch = min(sheets, max_amount)
			new stack_type(T, batch)
			sheets -= batch
	if(length(.))
		log_game("Salvage smelter [REF(src)] at [AREACOORD(src)] poured [json_encode(.)].")

/obj/machinery/recycling/salvage_smelter/examine(mob/user, infix = "", suffix = "")
	. = ..()
	for(var/material_name in salvage_melt)
		if(salvage_melt[material_name] >= 1)
			. += span_notice("Its melt holds [round(salvage_melt[material_name] / SHEET_MATERIAL_AMOUNT * 100)]% of a sheet of [material_name].")
