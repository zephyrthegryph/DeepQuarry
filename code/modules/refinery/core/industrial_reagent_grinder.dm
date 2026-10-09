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
	var/const/limit = 50
	VAR_PRIVATE/list/holdingitems = list()

/obj/machinery/reagent_refinery/grinder/Initialize(mapload)
	. = ..()
	default_apply_parts()

/obj/machinery/reagent_refinery/grinder/ownership()
	. = ..()
	. += owns(nameof(holdingitems), policy = OWN_SPILL, is_list = TRUE)

/// Requirement (was REQ_* has_room): the legacy check answers TRUE to pass.
/obj/machinery/reagent_refinery/grinder/proc/has_room_holds(datum/act/op/A)
	var/answer = has_room(A.actor, src, A.held)
	return !istext(answer) && !!answer

/// Why has_room_holds refuses: the legacy check's text, else the clause's own reason.
/obj/machinery/reagent_refinery/grinder/proc/has_room_refusal(datum/act/op/A)
	var/answer = has_room(A.actor, src, A.held)
	return istext(answer) ? answer : /datum/msg/req_failed

/// Requirement: the grinder holds at most `limit` items.
/obj/machinery/reagent_refinery/grinder/proc/has_room(mob/user, atom/target, obj/item/held)
	return length(holdingitems) >= limit ? "the machine cannot hold any more items" : TRUE

/obj/machinery/reagent_refinery/grinder/proc/interaction_insert(datum/act/op/A)
	var/mob/user = A.actor
	var/obj/item/O = A.held
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
			return OP_OK

		if(!contents_count(O))
			to_chat(user, "You empty \the [O] into \the [src].")
		else
			to_chat(user, "You fill \the [src] from \the [O].")
		return OP_OK

	// Borgos!
	if(istype(O,/obj/item/gripper))
		var/obj/item/gripper/B = O	//B, for Borg.
		var/obj/item/wrapped = B.get_wrapped_item()
		if(!wrapped)
			to_chat(user, "\The [B] is not holding anything.")
			return OP_OK
		else
			var/B_held = wrapped
			to_chat(user, "You use \the [B] to load \the [src] with \the [B_held].")
		return OP_OK

	// Needs to be sheet, ore, or grindable reagent containing things
	if(LAZYLEN(O.tool_qualities)) // Stops messages about the wrench being unsuitable to grind
		return OP_OK
	if(!GLOB.sheet_reagents[O.type] && !GLOB.ore_reagents[O.type] && (!O.reagents || !O.reagents.total_volume))
		to_chat(user, "\The [O] is not suitable for blending.")
		return OP_OK

	if(!move_into(src, nameof(src.holdingitems), O, user))
		return OP_OK
	return OP_OK

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
			if(C && !C.has_condition() && C.operating && C.dir == GLOB.reverse_dir[D] && contents_count(T) > 1) // If an operating conveyor points into us... Check if it's moving anything
				var/obj/item/I = pick(T.contents - list(C))
				if(istype(I) && conveyor_load(I))
					break

	if(holdingitems.len > 0 && grind_items_to_reagents(holdingitems,reagents))
		//Lazy coder sound design moment. THE SEQUEL
		play_sfx(src, SFX_ITEMS_POSTER_BEING_CREATED)
		play_sfx(src, SFX_ITEMS_ELECTRONIC_ASSEMBLY_EMPTYING)
		play_sfx(src, SFX_EFFECTS_METALSCRAPE2)
		if(holdingitems.len == 0)
			changed(src)

	refinery_transfer()

/obj/machinery/reagent_refinery/grinder/draw(datum/look/look)
	..()
	var/image/pipe = image(icon, icon_state = "grinder_cons", dir = dir)
	look.overlay(pipe)
	if(!operable() || !anchored)
		look.state("grinder_off")
	else
		look.state("grinder_on")
		var/image/dot = image(icon, icon_state = "grinder_dot_[length(holdingitems) ? "on" : "off" ]")
		look.overlay(dot)

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
		if(C && !C.has_condition() && C.operating && C.dir == GLOB.reverse_dir[D])
			return TRUE
	return FALSE

CAPABILITIES(/obj/machinery/reagent_refinery/grinder)
	without("reagent_refinery_set_transfer_amount")
	op("grinder_insert", item(/obj/item), priority(OP_PRIORITY_DEFAULT - 1), label("Insert"), needs(req_bool(PROC_REF(has_room_holds), because = PROC_REF(has_room_refusal))), then(PROC_REF(interaction_insert)))
