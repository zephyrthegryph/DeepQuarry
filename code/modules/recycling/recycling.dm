/obj/machinery/recycling
	idle_power_usage = 5
	active_power_usage = 500
	density = TRUE
	anchored = TRUE
	maintenance_flags = MACHINE_MAINT_STANDARD

	var/working = FALSE
	var/negative_dir = null // ition
	var/hand_fed = TRUE

/obj/machinery/recycling/Initialize(mapload)
	. = ..()
	default_apply_parts()

/obj/machinery/recycling/process()
	return PROCESS_KILL // these are all stateful

/obj/machinery/recycling/update_icon()
	. = ..()
	cut_overlays()
	if(panel_open)
		add_overlay("[initial(icon_state)]-panel")

/**
 * Generic procs common to all
 */
/obj/machinery/recycling/declare_interactions(list/into)
	into += list(
		/datum/interaction/machine_item/recycling_feed,
	)
	..()

/**
 * Old attackby: several silent guards (actor must be living and adjacent, not busy), then
 * part replacement, then hand-feeding. Kept as one interaction with the whole old body since
 * it never called ..() (unconditionally intercepts every item) and the guards mix silent
 * returns with messaged refusals.
 */
/datum/interaction/machine_item/recycling_feed
	id = "recycling_feed"
	name = "Feed"
	category = INTERACTION_CAT_INSERT
	held_type = /obj/item
	effect = /obj/machinery/recycling/proc/interaction_feed

/obj/machinery/recycling/proc/interaction_feed(mob/user, obj/item/O, datum/interaction/interaction)
	if(!isliving(user) || !Adjacent(user))
		return TRUE

	if(working)
		to_chat(user, span_warning("\The [src] is busy! Wait until it's idle."))
		return TRUE

	if(default_part_replacement(user, O))
		return TRUE
	if(!hand_fed)
		return TRUE
	var/mob/living/M = user
	if(can_accept_item(O))
		M.drop_from_inventory(O)
		take_item(O)
		M.visible_message(span_infoplain(span_bold("[M]") + " inserts [O] into [src]."), span_info("You insert [O] into [src]."))
	else
		to_chat(user, span_warning("\The [src] can't accept [O] for recycling."))
	return TRUE

// Conveyors etc
/obj/machinery/recycling/Bumped(atom/A)
	if(isitem(A) && can_accept_item(A))
		take_item(A)

/obj/machinery/recycling/proc/can_accept_item(obj/item/O)
	if(stat & (NOPOWER|BROKEN))
		return FALSE
	if(panel_open)
		return FALSE
	return !working

/obj/machinery/recycling/proc/take_item(obj/item/O)
	O.forceMove(src)

/**
 * This machine takes items and turns them into heaps of junk.
 */
/obj/machinery/recycling/crusher
	name = "recycling crusher"
	desc = "This machine is designed to break things into their constituient parts via the application of directed kinetic force. A.K.A. it crushes things into bits."
	icon = 'icons/obj/recycling.dmi'
	icon_state = "crusher"
	circuit = /obj/item/circuitboard/recycler_crusher

	working = FALSE
	var/effic_factor = 0.5

/obj/machinery/recycling/crusher/RefreshParts()
	. = ..()
	var/total_rating = get_part_rating(/obj/item/stock_parts/matter_bin) + get_part_rating(/obj/item/stock_parts/manipulator)

	total_rating *= 0.1

	effic_factor = CLAMP01(initial(effic_factor)+total_rating)

/obj/machinery/recycling/crusher/can_accept_item(obj/item/O)
	if(length(O.material_totals()))
		return ..()
	// ition Start - Let's the machine decide to put things it can't accept somewhere else.
	else if(negative_dir && isitem(O) && !ishuman(O.loc))
		O.forceMove(get_step(src, negative_dir))
	else
		return FALSE
	// ition End

/obj/machinery/recycling/crusher/take_item(obj/item/O)
	. = ..()
	var/trash = 1 // Trash multiplier
	working = TRUE
	icon_state = "crusher-process"
	update_use_power(USE_POWER_ACTIVE)
	sleep(5 SECONDS)
	var/list/modified_mats = list()
	if(istype(O,/obj/item/trash)) // Trash multiplier
		trash = 5 // Trash good
	if(istype(O,/obj/item/stack))
		var/obj/item/stack/S = O
		trash = S.amount
	var/list/item_matter = O.material_totals()
	for(var/mat in item_matter)
		modified_mats[mat] = item_matter[mat] * effic_factor * trash // Trash multiplier
	var/turf/T = get_step(src, dir)
	for(var/obj/item/debris_pack/D in T.contents)
		if(istype(D))
			D.add_materials(modified_mats)
			update_use_power(USE_POWER_IDLE)
			icon_state = "crusher"
			qdel(O)
			working = FALSE
			return
	new /obj/item/debris_pack(get_step(src, dir), modified_mats)
	update_use_power(USE_POWER_IDLE)
	icon_state = "crusher"
	qdel(O)
	working = FALSE

/**
 * This machine takes heaps of junk and holds onto them until it has enough of one material to make a sheet.
 */
/obj/machinery/recycling/sorter
	name = "debris sorter"
	desc = "A machine for retaining debris and sorting it until enough of a similar material have accumulated to warrant conversion into sheets or ingots."
	icon = 'icons/obj/recycling.dmi'
	icon_state = "sorter"
	circuit = /obj/item/circuitboard/recycler_sorter

	var/list/materials = list()
	working = FALSE

/obj/machinery/recycling/sorter/can_accept_item(obj/item/O)
	if(istype(O, /obj/item/debris_pack))
		return ..()
	return FALSE

/obj/machinery/recycling/sorter/take_item(obj/item/O)
	. = ..()
	working = TRUE
	icon_state = "sorter-process"
	update_use_power(USE_POWER_ACTIVE)
	sleep(2 SECONDS)
	sort_item(O)
	dispense_if_possible()
	update_use_power(USE_POWER_IDLE)
	icon_state = "sorter"
	working = FALSE

/obj/machinery/recycling/sorter/proc/sort_item(obj/item/O)
	var/list/item_matter = O.material_totals()
	for(var/mat in item_matter)
		if(mat in materials)
			materials[mat] += item_matter[mat]
		else
			materials[mat] = item_matter[mat]
	qdel(O)

/obj/machinery/recycling/sorter/proc/dispense_if_possible()
	for(var/mat in materials)
		while(materials[mat] >= (SHEET_MATERIAL_AMOUNT))
			materials[mat] -= (SHEET_MATERIAL_AMOUNT)
			new /obj/item/material_dust(get_step(src, dir), mat)
			sleep(2 SECONDS)

/**
 * This machine makes sheets after being provided with material dust from a sorter.
 */
/obj/machinery/recycling/stamper
	name = "sheet stamper"
	desc = "A machine to press homogenous material particulate into more solid portable units of production. A.K.A. it compacts dust into sheets."
	icon = 'icons/obj/recycling.dmi'
	icon_state = "stamper"
	circuit = /obj/item/circuitboard/recycler_stamper

/obj/machinery/recycling/stamper/can_accept_item(obj/item/O)
	if(istype(O, /obj/item/material_dust))
		return ..()
	return FALSE

/obj/machinery/recycling/stamper/take_item(obj/item/O)
	. = ..()
	working = TRUE
	icon_state = "stamper-process"
	update_use_power(USE_POWER_ACTIVE)
	sleep(64)
	dust_to_sheet(O)
	icon_state = "stamper"
	update_use_power(USE_POWER_IDLE)
	working = FALSE

/obj/machinery/recycling/stamper/proc/dust_to_sheet(obj/item/material_dust/D)
	if(!istype(D))
		return
	var/datum/material/M = get_material_by_name(D.material_name)
	if(!M)
		D.forceMove(get_step(src, dir))
		playsound(src, 'sound/machines/buzz-sigh.ogg', 50, 0)
		WARNING("Dust in [src] had material_name [D.material_name], which can't be made into stacks")
		return

	var/stacktype = M.stack_type
	var/turf/T = get_step(src, dir)
	var/obj/item/stack/S = locate(stacktype) in T
	if(S && S.get_amount() < S.max_amount)
		S.add(1)
	else
		new stacktype(T, 1)

/obj/item/debris_pack
	name = "debris"
	desc = "Some ground-up parts of ... something. Might be useful for recycling."
	icon = 'icons/obj/recycling.dmi'
	icon_state = "debris"
	w_class = ITEMSIZE_NORMAL

/obj/item/debris_pack/Initialize(mapload, list/matter_init)
	set_material_mix(matter_init.Copy())
	. = ..()

/obj/item/material_dust
	name = "dust"
	desc = "A homogenous powder of some material or another. Might be useful for recycling."
	icon = 'icons/obj/recycling.dmi'
	icon_state = "matdust"
	w_class = ITEMSIZE_SMALL
	var/material_name

/obj/item/material_dust/Initialize(mapload, mat)
	material_name = mat
	name = "[material_name] [initial(name)]"
	var/datum/material/M = get_material_by_name(material_name)
	color = M?.icon_colour
	. = ..()
