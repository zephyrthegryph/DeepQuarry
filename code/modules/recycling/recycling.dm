/obj/machinery/recycling
	idle_power_usage = 5
	active_power_usage = 500
	density = TRUE
	anchored = TRUE
	maintenance_flags = MACHINE_MAINT_STANDARD

	var/working = FALSE
	var/negative_dir = null // ition
	var/hand_fed = TRUE

// ALLOW(init/INSTANCE_STATE): takes the parts it was built with
/obj/machinery/recycling/Initialize(mapload)
	. = ..()
	default_apply_parts()

// Its periodic work: work_step() while it is started (code/library/machine/started_work.dm).
CAPABILITIES(/obj/machinery/recycling)
	started_work(step = PROC_REF(work_step))

/obj/machinery/recycling/proc/work_step(datum/act/timer/A)
	return PROCESS_KILL // these are all stateful

DECLARE_APPEARANCE(/obj/machinery/recycling, "panel_open", list("1" = list(APPEARANCE_OVERLAYS = list("-panel"))))
DECLARE_APPEARANCE(/obj/machinery/recycling/crusher, "panel_open", list("1" = list(APPEARANCE_OVERLAYS = list("crusher-panel"))))
DECLARE_APPEARANCE(/obj/machinery/recycling/sorter, "panel_open", list("1" = list(APPEARANCE_OVERLAYS = list("sorter-panel"))))
DECLARE_APPEARANCE(/obj/machinery/recycling/stamper, "panel_open", list("1" = list(APPEARANCE_OVERLAYS = list("stamper-panel"))))

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
	also_requires = list(REQ_FIELD_NOT("working", "it's busy; wait until it's idle"))

/obj/machinery/recycling/proc/interaction_feed(mob/user, obj/item/O, datum/interaction/interaction)
	if(!isliving(user) || !Adjacent(user))
		return TRUE

	if(default_part_replacement(user, O))
		return TRUE
	if(!hand_fed)
		return TRUE
	var/mob/living/M = user
	if(can_accept_item(O))
		M.drop_from_inventory(O)
		take_item(O)
		act_message(M, src, MSG_SELF(span_info("You insert [O] into %T%.")), MSG_OTHERS(span_infoplain(span_bold("%U%") + " inserts [O] into %T%.")))
	else
		to_chat(user, span_warning("\The [src] can't accept [O] for recycling."))
	return TRUE

// Conveyors etc
/obj/machinery/recycling/Bumped(atom/A)
	if(isitem(A) && can_accept_item(A))
		take_item(A)

/obj/machinery/recycling/proc/can_accept_item(obj/item/O)
	if(!operable())
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
	working = TRUE
	icon_state = "crusher-process"
	set_use_power(USE_POWER_ACTIVE)
	after(src, 5 SECONDS, PROC_REF(crush_done), with = list(O))

/obj/machinery/recycling/crusher/proc/crush_done(obj/item/O)
	var/trash = 1 // Trash multiplier
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
	for(var/obj/item/debris_pack/D in turf_contents_of_type(T, /obj/item/debris_pack))
		if(istype(D))
			D.add_materials(modified_mats)
			set_use_power(USE_POWER_IDLE)
			icon_state = "crusher"
			destroyed(O, src, BRUTE)
			working = FALSE
			return
	new /obj/item/debris_pack(get_step(src, dir), modified_mats)
	set_use_power(USE_POWER_IDLE)
	icon_state = "crusher"
	destroyed(O, src, BRUTE)
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

	var/list/materials = list() // ALLOW(instance_list): d: sorter filter table set at init
	working = FALSE

/// TRUE while it hands out dust piles (after a sort): dispense_if_possible() every 2 seconds.
OM_FIELD(/obj/machinery/recycling/sorter, dispensing, FALSE, CHANGE_MACHINE_SETTINGS)
DECLARE_REPEAT(/obj/machinery/recycling/sorter, 2 SECONDS, dispense_if_possible, "dispensing")

/obj/machinery/recycling/sorter/can_accept_item(obj/item/O)
	if(istype(O, /obj/item/debris_pack))
		return ..()
	return FALSE

/obj/machinery/recycling/sorter/take_item(obj/item/O)
	. = ..()
	working = TRUE
	icon_state = "sorter-process"
	set_use_power(USE_POWER_ACTIVE)
	after(src, 2 SECONDS, PROC_REF(sort_done), with = list(O))

/obj/machinery/recycling/sorter/proc/sort_done(obj/item/O)
	sort_item(O)
	set_dispensing(TRUE)

/obj/machinery/recycling/sorter/proc/sort_item(obj/item/O)
	var/list/item_matter = O.material_totals()
	for(var/mat in item_matter)
		if(mat in materials)
			materials[mat] += item_matter[mat]
		else
			materials[mat] = item_matter[mat]
	consumed(O, src)

/// Dispenses one dust pile every 2 seconds (declared: while dispensing) while any material has a
/// sheet's worth, then idles.
/obj/machinery/recycling/sorter/proc/dispense_if_possible()
	for(var/mat in materials)
		if(materials[mat] >= (SHEET_MATERIAL_AMOUNT))
			materials[mat] -= (SHEET_MATERIAL_AMOUNT)
			new /obj/item/material_dust(get_step(src, dir), mat)
			return
	set_dispensing(FALSE)
	set_use_power(USE_POWER_IDLE)
	icon_state = "sorter"
	working = FALSE
	return REPEAT_STOP

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
	set_use_power(USE_POWER_ACTIVE)
	after(src, 6.4 SECONDS, PROC_REF(stamp_done), with = list(O))

/obj/machinery/recycling/stamper/proc/stamp_done(obj/item/O)
	dust_to_sheet(O)
	icon_state = "stamper"
	set_use_power(USE_POWER_IDLE)
	working = FALSE

/obj/machinery/recycling/stamper/proc/dust_to_sheet(obj/item/material_dust/D)
	if(!istype(D))
		return
	var/datum/material/M = get_material_by_name(D.material_name)
	if(!M)
		D.forceMove(get_step(src, dir))
		play_sfx(src, SFX_MACHINES_BUZZ_SIGH)
		WARNING("Dust in [src] had material_name [D.material_name], which can't be made into stacks")
		return

	var/stacktype = M.stack_type
	var/turf/T = get_step(src, dir)
	var/obj/item/stack/S = locate_on(T, stacktype)
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

CAPABILITIES(/obj/item/debris_pack)
	param(nameof(matter_at_make), pos = 1, apply = PROC_REF(hold_matter), keep = FALSE)

/// The matter a debris pack holds (its constructor param, dropped once set).
/obj/item/debris_pack/var/tmp/list/matter_at_make

/// Applied at init from its constructor param (param(apply =), code/engine/lifeforms/params.dm).
/obj/item/debris_pack/proc/hold_matter(list/matter_init)
	set_material_mix(matter_init?.Copy())

/obj/item/material_dust
	name = "dust"
	desc = "A homogenous powder of some material or another. Might be useful for recycling."
	icon = 'icons/obj/recycling.dmi'
	icon_state = "matdust"
	w_class = ITEMSIZE_SMALL
	var/material_name

CAPABILITIES(/obj/item/material_dust)
	param(nameof(material_name), pos = 1, apply = PROC_REF(dust_of))

/// Applied at init from its constructor param (param(apply =), code/engine/lifeforms/params.dm). The dust is named and coloured for its material.
/obj/item/material_dust/proc/dust_of(mat)
	name = "[material_name] [initial(name)]"
	var/datum/material/M = get_material_by_name(material_name)
	color = M?.icon_colour
