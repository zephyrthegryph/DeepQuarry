/obj/machinery/floorlayer
	name = "automatic floor layer"
	icon = 'icons/obj/stationobjs.dmi'
	icon_state = "pipe_d"
	density = TRUE
	var/turf/old_turf
	on = 0
	var/obj/item/stack/tile/T
	var/list/work_modes = list("dismantle"=0,"laying"=0,"collect"=0) // ALLOW(instance_list): d: edited in place per instance (3 writers)

/obj/machinery/floorlayer/Moved(atom/old_loc, direction, forced = FALSE)
	. = ..()

	if(on)
		if(work_modes["dismantle"])
			dismantleFloor(old_turf())

		if(work_modes["laying"])
			layFloor(old_turf())

		if(work_modes["collect"])
			CollectTiles(old_turf())

	rel_set(src, nameof(old_turf), loc)

CAPABILITIES(/obj/machinery/floorlayer)
	op("floorlayer_toggle", hand(), ungated(), priority(OP_PRIORITY_DEFAULT - 1), label("Toggle"), then(PROC_REF(interaction_toggle)))
	op("floorlayer_load_tile", item(/obj/item/stack/tile), priority(OP_PRIORITY_DEFAULT - 1), label("Load tile"), then(PROC_REF(interaction_load_tile)))

/obj/machinery/floorlayer/proc/interaction_toggle(datum/act/op/A)
	var/mob/user = A.actor
	set_on(!on)
	act_message(user, src, MSG_SELF(span_notice("You [!on?"de":""]activate %T%.")), MSG_OTHERS(span_notice("%U% has [!on?"de":""]activated %T%.")))
	return OP_OK

/obj/machinery/floorlayer/proc/interaction_load_tile(datum/act/op/A)
	var/mob/user = A.actor
	var/obj/item/W = A.held
	if(!own_bring_in(src, nameof(contents), W, null, user, TRUE, null, FALSE))
		return OP_OK
	to_chat(user, span_notice("\The [W] successfully loaded."))
	TakeTile(W)
	return OP_OK

/obj/machinery/floorlayer/wrench_act(mob/user, obj/item/tool)
	open_request(src, /datum/prompt/choice, PROC_REF(work_mode_chosen), answerer = user, title = "Mode", question = "Choose work mode", choices = work_modes, ask_flags = ASK_ADJACENT | ASK_CAPABLE, timeout = 0)
	return ITEM_INTERACT_SUCCESS

/obj/machinery/floorlayer/proc/work_mode_chosen(datum/act/request/A)
	if(!A.answer)
		return
	var/mob/user = A.request.answerer
	var/selected_mode = A.answer.value
	work_modes[selected_mode] = !work_modes[selected_mode]
	act_message(user, src, MSG_SELF(span_notice("You set %T% [selected_mode] mode [work_modes[selected_mode] ? "on" : "off"].")), \
		MSG_OTHERS(span_notice("%U% has set %T% [selected_mode] mode [work_modes[selected_mode] ? "on" : "off"].")))
	return ITEM_INTERACT_SUCCESS

/obj/machinery/floorlayer/crowbar_act(mob/user, obj/item/tool)
	if(!contents_count(src) && !has_latent()) // ALLOW(latent): latent entries checked
		to_chat(user, span_notice("\The [src] is empty."))
		return ITEM_INTERACT_BLOCKING
	open_request(src, /datum/prompt/choice, PROC_REF(tile_removal_chosen), answerer = user, title = "Tiles", question = "Choose remove tile type.", choices = contents, ask_flags = ASK_ADJACENT | ASK_CAPABLE, timeout = 0)
	return ITEM_INTERACT_SUCCESS

/obj/machinery/floorlayer/proc/tile_removal_chosen(datum/act/request/A)
	if(!A.answer)
		return
	var/mob/user = A.request.answerer
	var/obj/item/stack/tile/selected = A.answer.value
	if(selected.loc != src)
		return
	if(selected)
		to_chat(user, span_notice("You remove [selected] from \the [src]."))
		selected.forceMove(loc)
		own_take(src, nameof(T))
	return ITEM_INTERACT_SUCCESS

/obj/machinery/floorlayer/screwdriver_act(mob/user, obj/item/tool)
	open_request(src, /datum/prompt/choice, PROC_REF(tile_type_chosen), answerer = user, title = "Tiles", question = "Choose tile type.", choices = contents, ask_flags = ASK_ADJACENT | ASK_CAPABLE, timeout = 0)
	return ITEM_INTERACT_SUCCESS

/obj/machinery/floorlayer/proc/tile_type_chosen(datum/act/request/A)
	if(!A.answer)
		return
	var/obj/item/stack/tile/selected = A.answer.value
	if(selected.loc == src)
		rel_set(src, nameof(T), selected)

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
	for(var/obj/item/stack/tile/tile in contents) // ALLOW(latent): the contents were materialized by an earlier latent_materialize_all() in this proc, so this scan sees real objects
		rel_set(src, nameof(T), tile)
		return 1
	return 0

/obj/machinery/floorlayer/proc/SortStacks()
	latent_materialize_all() // a walk needs real things (C5)
	for(var/obj/item/stack/tile/tile1 in contents) // ALLOW(latent): the contents were materialized by an earlier latent_materialize_all() in this proc, so this scan sees real objects
		for(var/obj/item/stack/tile/tile2 in contents) // ALLOW(latent): the contents were materialized by an earlier latent_materialize_all() in this proc, so this scan sees real objects
			if(tile2 != tile1)
				tile2.transfer_to(tile1)

/obj/machinery/floorlayer/proc/layFloor(turf/w_turf)
	if(!T)
		if(!TakeNewStack())
			return 0
	w_turf.attackby(T , src)
	return 1

/obj/machinery/floorlayer/proc/TakeTile(obj/item/stack/tile/tile)
	if(!T)
		move_into(src, nameof(src.T), tile)
	else
		tile.forceMove(src)

	SortStacks()

/obj/machinery/floorlayer/proc/CollectTiles(turf/w_turf)
	for(var/obj/item/stack/tile/tile in turf_contents_of_type(w_turf, /obj/item/stack/tile))
		TakeTile(tile)

/obj/machinery/floorlayer/ownership()
	. = ..()
	. += owns(nameof(T), policy = OWN_CONTAINED, starts = /obj/item/stack/tile/floor)

/// old turf (a relation view: it reads null once the target is deleted).
/obj/machinery/floorlayer/proc/old_turf() as /turf
	return old_turf
