/obj/machinery/floorlayer
	name = "automatic floor layer"
	icon = 'icons/obj/stationobjs.dmi'
	icon_state = "pipe_d"
	density = TRUE
	var/turf/old_turf
	on = 0
	var/obj/item/stack/tile/T
	var/list/work_modes = list("dismantle"=0,"laying"=0,"collect"=0) // ALLOW(instance_list): d: edited in place per instance (3 writers)

DECLARE_DEFAULT_CHILD(/obj/machinery/floorlayer, "T", /obj/item/stack/tile/floor)

/obj/machinery/floorlayer/Moved(atom/old_loc, direction, forced = FALSE)
	. = ..()

	if(on)
		if(work_modes["dismantle"])
			dismantleFloor(old_turf())

		if(work_modes["laying"])
			layFloor(old_turf())

		if(work_modes["collect"])
			CollectTiles(old_turf())


	rel_set(src, "old_turf", loc)

/obj/machinery/floorlayer/declare_interactions(list/into)
	into += list(
		/datum/interaction/machine_hand/ungated/floorlayer_toggle,
		/datum/interaction/machine_item/floorlayer_load_tile,
	)
	..()

/// Old attack_hand: never called ..(), so it works without power.
/datum/interaction/machine_hand/ungated/floorlayer_toggle
	id = "floorlayer_toggle"
	name = "Toggle"
	category = INTERACTION_CAT_TOGGLE
	effect = /obj/machinery/floorlayer/proc/interaction_toggle

/obj/machinery/floorlayer/proc/interaction_toggle(mob/user, obj/item/held, datum/interaction/interaction)
	set_on(!on)
	act_message(user, src, MSG_SELF(span_notice("You [!on?"de":""]activate %T%.")), MSG_OTHERS(span_notice("%U% has [!on?"de":""]activated %T%.")))
	return TRUE

/// Old attackby: load a tile stack.
/datum/interaction/machine_item/floorlayer_load_tile
	id = "floorlayer_load_tile"
	name = "Load tile"
	category = INTERACTION_CAT_INSERT
	held_type = /obj/item/stack/tile
	effect = /obj/machinery/floorlayer/proc/interaction_load_tile

/obj/machinery/floorlayer/proc/interaction_load_tile(mob/user, obj/item/W, datum/interaction/interaction)
	to_chat(user, span_notice("\The [W] successfully loaded."))
	user.drop_item(W)
	TakeTile(W)
	return TRUE

/obj/machinery/floorlayer/wrench_act(mob/user, obj/item/tool)
	om_ask(user, /datum/om/prompt/choice, PROC_REF(work_mode_chosen), message = "Choose work mode", title = "Mode", choices = work_modes, requires = PROMPT_ADJACENT)
	return ITEM_INTERACT_SUCCESS

/obj/machinery/floorlayer/proc/work_mode_chosen(datum/om/prompt/choice/ask)
	var/mob/user = ask.answerer
	var/selected_mode = ask.choice
	work_modes[selected_mode] = !work_modes[selected_mode]
	act_message(user, src, MSG_SELF(span_notice("You set %T% [selected_mode] mode [work_modes[selected_mode] ? "on" : "off"].")), \
		MSG_OTHERS(span_notice("%U% has set %T% [selected_mode] mode [work_modes[selected_mode] ? "on" : "off"].")))
	return ITEM_INTERACT_SUCCESS

/obj/machinery/floorlayer/crowbar_act(mob/user, obj/item/tool)
	if(!contents_count(src) && !has_latent()) // ALLOW(latent): latent entries checked
		to_chat(user, span_notice("\The [src] is empty."))
		return ITEM_INTERACT_BLOCKING
	om_ask(user, /datum/om/prompt/choice, PROC_REF(tile_removal_chosen), message = "Choose remove tile type.", title = "Tiles", choices = contents, requires = PROMPT_ADJACENT)
	return ITEM_INTERACT_SUCCESS

/obj/machinery/floorlayer/proc/tile_removal_chosen(datum/om/prompt/choice/ask)
	var/mob/user = ask.answerer
	var/obj/item/stack/tile/selected = ask.choice
	if(selected.loc != src)
		return
	if(selected)
		to_chat(user, span_notice("You remove [selected] from \the [src]."))
		selected.forceMove(loc)
		own_take(src, "T")
	return ITEM_INTERACT_SUCCESS

/obj/machinery/floorlayer/screwdriver_act(mob/user, obj/item/tool)
	om_ask(user, /datum/om/prompt/choice, PROC_REF(tile_type_chosen), message = "Choose tile type.", title = "Tiles", choices = contents, requires = PROMPT_ADJACENT)
	return ITEM_INTERACT_SUCCESS

/obj/machinery/floorlayer/proc/tile_type_chosen(datum/om/prompt/choice/ask)
	var/obj/item/stack/tile/selected = ask.choice
	if(selected.loc == src)
		own_set(src, "T", selected)

/obj/machinery/floorlayer/examine(mob/user)
	. = ..()
	var/dismantle = work_modes["dismantle"]
	var/laying = work_modes["laying"]
	var/collect = work_modes["collect"]
	. += span_notice("[src] [!T ? "don't " : ""]has [!T ? "" : "[T.get_amount()] [T] "]tile\s, dismantle is [dismantle ? "on" : "off"], laying is [laying ? "on" : "off"], collect is [collect ? "on" : "off"].")

/obj/machinery/floorlayer/proc/reset()
	set_on(0)
	return

/obj/machinery/floorlayer/proc/dismantleFloor(turf/new_turf)
	if(istype(new_turf, /turf/simulated/floor))
		var/turf/simulated/floor/T = new_turf
		if(!T.is_plating())
			T.make_plating(!(T.broken || T.burnt))
	return new_turf.is_plating()

/obj/machinery/floorlayer/proc/TakeNewStack()
	latent_materialize_all() // a walk needs real things (C5)
	for(var/obj/item/stack/tile/tile in contents) // ALLOW(latent): materialized above
		own_set(src, "T", tile)
		return 1
	return 0

/obj/machinery/floorlayer/proc/SortStacks()
	latent_materialize_all() // a walk needs real things (C5)
	for(var/obj/item/stack/tile/tile1 in contents) // ALLOW(latent): materialized above
		for(var/obj/item/stack/tile/tile2 in contents) // ALLOW(latent): materialized above
			tile2.transfer_to(tile1)

/obj/machinery/floorlayer/proc/layFloor(turf/w_turf)
	if(!T)
		if(!TakeNewStack())
			return 0
	w_turf.attackby(T , src)
	return 1

/obj/machinery/floorlayer/proc/TakeTile(obj/item/stack/tile/tile)
	tile.forceMove(src)
	if(!T)
		own_set(src, "T", tile)

	SortStacks()

/obj/machinery/floorlayer/proc/CollectTiles(turf/w_turf)
	for(var/obj/item/stack/tile/tile in turf_contents_of_type(w_turf, /obj/item/stack/tile))
		TakeTile(tile)

OWN(/obj/machinery/floorlayer, T, OWN_CONTAINED)

/// old turf (a relation view: it reads null once the target is deleted).
/obj/machinery/floorlayer/proc/old_turf() as /turf
	return old_turf
