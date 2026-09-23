/obj/machinery/floorlayer
	name = "automatic floor layer"
	icon = 'icons/obj/stationobjs.dmi'
	icon_state = "pipe_d"
	density = TRUE
	var/turf/old_turf
	var/on = 0
	var/obj/item/stack/tile/T
	var/list/mode = list("dismantle"=0,"laying"=0,"collect"=0)

/obj/machinery/floorlayer/Initialize(mapload)
	. = ..()
	T = new/obj/item/stack/tile/floor(src)

/obj/machinery/floorlayer/Moved(atom/old_loc, direction, forced = FALSE)
	. = ..()

	if(on)
		if(mode["dismantle"])
			dismantleFloor(old_turf)

		if(mode["laying"])
			layFloor(old_turf)

		if(mode["collect"])
			CollectTiles(old_turf)


	old_turf = loc

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
	on = !on
	user.visible_message(span_notice("[user] has [!on?"de":""]activated \the [src]."), span_notice("You [!on?"de":""]activate \the [src]."))
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
	var/selected_mode = tgui_input_list(user, "Choose work mode", "Mode", mode)
	if(!selected_mode)
		return ITEM_INTERACT_BLOCKING
	mode[selected_mode] = !mode[selected_mode]
	user.visible_message(span_notice("[user] has set \the [src] [selected_mode] mode [mode[selected_mode] ? "on" : "off"]."), span_notice("You set \the [src] [selected_mode] mode [mode[selected_mode] ? "on" : "off"]."))
	return ITEM_INTERACT_SUCCESS

/obj/machinery/floorlayer/crowbar_act(mob/user, obj/item/tool)
	if(!length(contents))
		to_chat(user, span_notice("\The [src] is empty."))
		return ITEM_INTERACT_BLOCKING
	var/obj/item/stack/tile/selected = tgui_input_list(user, "Choose remove tile type.", "Tiles", contents)
	if(selected)
		to_chat(user, span_notice("You remove [selected] from \the [src]."))
		selected.forceMove(loc)
		T = null
	return ITEM_INTERACT_SUCCESS

/obj/machinery/floorlayer/screwdriver_act(mob/user, obj/item/tool)
	T = tgui_input_list(user, "Choose tile type.", "Tiles", contents)
	return ITEM_INTERACT_SUCCESS

/obj/machinery/floorlayer/examine(mob/user)
	. = ..()
	var/dismantle = mode["dismantle"]
	var/laying = mode["laying"]
	var/collect = mode["collect"]
	. += span_notice("[src] [!T ? "don't " : ""]has [!T ? "" : "[T.get_amount()] [T] "]tile\s, dismantle is [dismantle ? "on" : "off"], laying is [laying ? "on" : "off"], collect is [collect ? "on" : "off"].")

/obj/machinery/floorlayer/proc/reset()
	on=0
	return

/obj/machinery/floorlayer/proc/dismantleFloor(turf/new_turf)
	if(istype(new_turf, /turf/simulated/floor))
		var/turf/simulated/floor/T = new_turf
		if(!T.is_plating())
			T.make_plating(!(T.broken || T.burnt))
	return new_turf.is_plating()

/obj/machinery/floorlayer/proc/TakeNewStack()
	for(var/obj/item/stack/tile/tile in contents)
		T = tile
		return 1
	return 0

/obj/machinery/floorlayer/proc/SortStacks()
	for(var/obj/item/stack/tile/tile1 in contents)
		for(var/obj/item/stack/tile/tile2 in contents)
			tile2.transfer_to(tile1)

/obj/machinery/floorlayer/proc/layFloor(turf/w_turf)
	if(!T)
		if(!TakeNewStack())
			return 0
	w_turf.attackby(T , src)
	return 1

/obj/machinery/floorlayer/proc/TakeTile(obj/item/stack/tile/tile)
	if(!T)	T = tile
	tile.loc = src

	SortStacks()

/obj/machinery/floorlayer/proc/CollectTiles(turf/w_turf)
	for(var/obj/item/stack/tile/tile in w_turf)
		TakeTile(tile)
