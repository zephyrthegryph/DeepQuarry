/obj/machinery/reagent_refinery/grinder
	name = "Industrial Chemical Grinder"
	desc = "Grinds anything and everything into chemical slurry."
	icon_state = "grinder_off"
	density = TRUE
	anchored = TRUE
	use_power = USE_POWER_IDLE
	idle_power_usage = 5
	active_power_usage = 300
	circuit = /obj/item/circuitboard/industrial_reagent_grinder
	var/static/limit = 50
	VAR_PRIVATE/list/holdingitems = list()

/obj/machinery/reagent_refinery/grinder/Initialize(mapload)
	. = ..()
	default_apply_parts()
	// Update neighbours and self for state
	update_neighbours()
	update_icon()

/obj/machinery/reagent_refinery/grinder/ownership()
	. = ..()
	. += owns(nameof(holdingitems), policy = OWN_SPILL, is_list = TRUE)

/obj/machinery/reagent_refinery/grinder/declare_interactions(list/into)
	// Old attackby tried the parent's attackby FIRST, only falling to its own
	// logic when the parent declined: the parent's own interactions come
	// before this type's, the reverse of the usual override-chain order.
	..()
	into += list(
		/datum/interaction/machine_item/grinder_insert,
	)

/// Old attackby: insert grindables when the parent attackby didn't handle it.
/datum/interaction/machine_item/grinder_insert
	id = "grinder_insert"
	name = "Insert"
	category = INTERACTION_CAT_INSERT
	held_type = /obj/item
	effect = /obj/machinery/reagent_refinery/grinder/proc/interaction_insert
	also_requires = list(REQ_TARGET_STATE(/obj/machinery/reagent_refinery/grinder/proc/has_room))

/// Requirement: the grinder holds at most `limit` items.
/obj/machinery/reagent_refinery/grinder/proc/has_room(mob/user, atom/target, obj/item/held)
	return length(holdingitems) >= limit ? "the machine cannot hold any more items" : TRUE

/obj/machinery/reagent_refinery/grinder/proc/interaction_insert(mob/user, obj/item/O, datum/interaction/interaction)
	// Botany/Chemistry gameplay
	if(istype(O,/obj/item/storage/bag))
		var/failed = 1
		for(var/obj/item/G in contents_of(O))
			if(!G.reagents || !G.reagents.total_volume)
				continue
			failed = 0
			rel_add(src, nameof(src.holdingitems), G) // out of the bag: a one-call transfer
			if(holdingitems && holdingitems.len >= limit)
				break

		if(failed)
			to_chat(user, "Nothing in \the [O] is usable.")
			return TRUE

		if(!contents_count(O))
			to_chat(user, "You empty \the [O] into \the [src].")
		else
			to_chat(user, "You fill \the [src] from \the [O].")
		return TRUE

	// Borgos!
	if(istype(O,/obj/item/gripper))
		var/obj/item/gripper/B = O	//B, for Borg.
		var/obj/item/wrapped = B.get_wrapped_item()
		if(!wrapped)
			to_chat(user, "\The [B] is not holding anything.")
			return TRUE
		else
			var/B_held = wrapped
			to_chat(user, "You use \the [B] to load \the [src] with \the [B_held].")
		return TRUE

	// Needs to be sheet, ore, or grindable reagent containing things
	if(LAZYLEN(O.tool_qualities)) // Stops messages about the wrench being unsuitable to grind
		return TRUE
	if(!GLOB.sheet_reagents[O.type] && !GLOB.ore_reagents[O.type] && (!O.reagents || !O.reagents.total_volume))
		to_chat(user, "\The [O] is not suitable for blending.")
		return TRUE

	if(!move_into(src, nameof(src.holdingitems), O, user))
		return TRUE
	update_icon()
	return TRUE

/obj/machinery/reagent_refinery/grinder/refinery_step()
	if(!anchored)
		return

	power_change()
	if(!operable())
		return

	// Get objects from incoming conveyors
	if(holdingitems.len < limit)
		for(var/D in GLOB.cardinal)
			var/turf/T = get_step(src,D)
			if(!T)
				continue
			var/obj/machinery/conveyor/C = locate_on(T, /obj/machinery/conveyor)
			if(C && !C.has_stat(MACHINE_STAT_ANY) && C.operating && C.dir == GLOB.reverse_dir[D] && contents_count(T) > 1) // If an operating conveyor points into us... Check if it's moving anything
				var/obj/item/I = pick(T.contents - list(C))
				if(istype(I) && conveyor_load(I))
					break

	if(holdingitems.len > 0 && grind_items_to_reagents(holdingitems,reagents))
		//Lazy coder sound design moment. THE SEQUEL
		play_sfx(src, SFX_ITEMS_POSTER_BEING_CREATED)
		play_sfx(src, SFX_ITEMS_ELECTRONIC_ASSEMBLY_EMPTYING)
		play_sfx(src, SFX_EFFECTS_METALSCRAPE2)
		if(holdingitems.len == 0)
			update_icon()

	refinery_transfer()

DECLARE_APPEARANCE_PROC(/obj/machinery/reagent_refinery/grinder, TYPE_PROC_REF(/atom, appearance_overlays), list())
/obj/machinery/reagent_refinery/grinder/appearance_overlays()
	. = list()
	var/image/pipe = image(icon, icon_state = "grinder_cons", dir = dir)
	. += pipe
	if(!operable() || !anchored)
		icon_state = "grinder_off"
	else
		icon_state = "grinder_on"
		var/image/dot = image(icon, icon_state = "grinder_dot_[length(holdingitems) ? "on" : "off" ]")
		. += dot

/obj/machinery/reagent_refinery/grinder/proc/conveyor_load(atom/movable/AM as mob|obj)
	if(!AM || QDELETED(AM))
		return FALSE
	if(holdingitems.len >= limit)
		return FALSE
	if(ismob(AM)) // No mob bumping YET
		return FALSE
	if(!GLOB.sheet_reagents[AM.type] && !GLOB.ore_reagents[AM.type] && (!AM.reagents || !AM.reagents.total_volume))
		return FALSE
	move_into(src, nameof(src.holdingitems), AM)
	return TRUE

/obj/machinery/reagent_refinery/grinder/examine(mob/user, infix, suffix)
	. = ..()
	. += "The intake cache shows [length(holdingitems)] / [limit] grindable items."
	. += "The meter shows [reagents.total_volume]u / [reagents.maximum_volume]u. It is pumping chemicals at a rate of [amount_per_transfer_from_this]u."
	tutorial(REFINERY_TUTORIAL_NOINPUT, .)

/obj/machinery/reagent_refinery/grinder/handle_transfer(atom/origin_machine, datum/reagents/RT, source_forward_dir, transfer_rate, filter_id = "")
	// Grinder forbids input
	return 0


/// Busy while it holds items to grind or an operating conveyor feeds it.
/obj/machinery/reagent_refinery/grinder/refinery_busy()
	if(length(holdingitems))
		return TRUE
	for(var/D in GLOB.cardinal)
		var/obj/machinery/conveyor/C = locate_within(get_step(src, D), /obj/machinery/conveyor)
		if(C && !C.has_stat(MACHINE_STAT_ANY) && C.operating && C.dir == GLOB.reverse_dir[D])
			return TRUE
	return FALSE

CAPABILITIES(/obj/machinery/reagent_refinery/grinder)
	without("reagent_refinery_set_transfer_amount")
