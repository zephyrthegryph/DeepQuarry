/obj/item/mecha_parts/mecha_equipment/tool/cable_layer
	name = "Cable Layer"
	icon_state = "mecha_wire"
	var/turf/old_turf
	var/obj/structure/cable/last_piece
	var/obj/item/stack/cable_coil/cable
	var/max_cable = 1000
	required_type = list(/obj/mecha/working)

/obj/item/mecha_parts/mecha_equipment/tool/cable_layer/Initialize(mapload)
	. = ..()
	rel_set(src, nameof(cable), new /obj/item/stack/cable_coil(src, 0))

/obj/item/mecha_parts/mecha_equipment/tool/cable_layer/MoveAction()
	layCable()

/obj/item/mecha_parts/mecha_equipment/tool/cable_layer/action(obj/item/stack/cable_coil/target)
	if(!action_checks(target))
		return
	var/result = load_cable(target)
	var/message
	if(isnull(result))
		message = span_red("Unable to load [target] - no cable found.")
	else if(!result)
		message = "Reel is full."
	else
		message = "[result] meters of cable successfully loaded."
		send_byjax(chassis?.slot_item(MECHA_SLOT_PILOT),"exosuit.browser","\ref[src]",src.get_equip_info())
	occupant_message(message)
	return

TOPIC_ACTION(/obj/item/mecha_parts/mecha_equipment/tool/cable_layer, "toggle", PROC_REF(topic_toggle))
TOPIC_ACTION(/obj/item/mecha_parts/mecha_equipment/tool/cable_layer, "cut", PROC_REF(topic_cut))

/obj/item/mecha_parts/mecha_equipment/tool/cable_layer/proc/topic_toggle(mob/user, list/args)
	set_ready_state(!equip_ready)
	occupant_message("[src] [equip_ready?"dea":"a"]ctivated.")
	src.mecha_log_message("[equip_ready?"Dea":"A"]ctivated.")

/obj/item/mecha_parts/mecha_equipment/tool/cable_layer/proc/topic_cut(mob/user, list/args)
	if(cable && cable.get_amount())
		var/mob/pilot = chassis?.slot_item(MECHA_SLOT_PILOT)
		if(!istype(pilot) || QDELETED(pilot))
			return
		open_request(src, /datum/prompt/number/mecha_cable_cut, PROC_REF(cable_length_entered), answerer = pilot, default = min(cable.get_amount(), 30), subject = chassis)
	else
		occupant_message("There's no more cable on the reel.")
	return

/obj/item/mecha_parts/mecha_equipment/tool/cable_layer/proc/cable_length_entered(datum/act/request/context)
	if(!context.answer)
		return
	var/datum/prompt/number/mecha_cable_cut/ask = context.answer
	if(!cable)
		return
	var/m = min(ask.value, cable.get_amount())
	if(m)
		use_cable(m)
		new /obj/item/stack/cable_coil(get_turf(chassis), m)

/obj/item/mecha_parts/mecha_equipment/tool/cable_layer/get_equip_info()
	var/output = ..()
	if(output)
		return "[output] \[Cable: [cable ? cable.get_amount() : 0] m\][(cable && cable.get_amount()) ? "- <a href='byond://?src=\ref[src];toggle=1'>[!equip_ready?"Dea":"A"]ctivate</a>|<a href='byond://?src=\ref[src];cut=1'>Cut</a>" : null]"
	return

/obj/item/mecha_parts/mecha_equipment/tool/cable_layer/proc/load_cable(obj/item/stack/cable_coil/CC)
	if(istype(CC) && CC.get_amount())
		var/cur_amount = cable? cable.get_amount() : 0
		var/to_load = max(max_cable - cur_amount,0)
		if(to_load)
			to_load = min(CC.get_amount(), to_load)
			if(!cable)
				rel_set(src, nameof(cable), new /obj/item/stack/cable_coil(src, to_load))
			else
				cable.add(to_load)
			CC.use(to_load)
			return to_load
		else
			return 0
	return

/obj/item/mecha_parts/mecha_equipment/tool/cable_layer/proc/use_cable(amount)
	if(!cable || cable.get_amount() < 1)
		set_ready_state(TRUE)
		occupant_message("Cable depleted, [src] deactivated.")
		src.mecha_log_message("Cable depleted, [src] deactivated.")
		return
	if(cable.get_amount() < amount)
		occupant_message("No enough cable to finish the task.")
		return
	cable.use(amount)
	update_equip_info()
	return 1

/obj/item/mecha_parts/mecha_equipment/tool/cable_layer/proc/reset()
	rel_clear(src, nameof(last_piece))

/obj/item/mecha_parts/mecha_equipment/tool/cable_layer/proc/dismantleFloor(turf/new_turf)
	new_turf = get_turf(chassis)
	if(istype(new_turf, /turf/simulated/floor))
		var/turf/simulated/floor/T = new_turf
		if(!T.is_plating())
			T.make_plating(!(T.broken || T.burnt))
	return new_turf.is_plating()

/obj/item/mecha_parts/mecha_equipment/tool/cable_layer/proc/layCable(turf/new_turf)
	new_turf = get_turf(chassis)
	if(equip_ready || !istype(new_turf, /turf/simulated/floor) || !dismantleFloor(new_turf))
		return reset()
	var/fdirn = turn(chassis.dir,180)
	for(var/obj/structure/cable/LC in turf_contents_of_type(new_turf, /obj/structure/cable))		// check to make sure there's not a cable there already
		if(LC.d1 == fdirn || LC.d2 == fdirn)
			return reset()
	if(!use_cable(1))
		return reset()
	var/obj/structure/cable/NC = new(new_turf)
	NC.cableColor("red")
	NC.d1 = 0
	NC.d2 = fdirn
	changed(NC)

	if(last_piece() && last_piece().d2 != chassis.dir)
		last_piece().d1 = min(last_piece().d2, chassis.dir)
		last_piece().d2 = max(last_piece().d2, chassis.dir)
		changed(last_piece())
		last_piece().power_register()
	NC.power_register()
	rel_set(src, nameof(last_piece), NC)
	return 1

/obj/item/mecha_parts/mecha_equipment/tool/cable_layer/ownership()
	. = ..()
	. += owns(nameof(cable), policy = OWN_CONTAINED)

/// old turf
/obj/item/mecha_parts/mecha_equipment/tool/cable_layer/proc/old_turf() as /turf
	return old_turf

/// last piece
/obj/item/mecha_parts/mecha_equipment/tool/cable_layer/proc/last_piece() as /obj/structure/cable
	return last_piece

/datum/prompt/number/mecha_cable_cut
	title = "Cut cable"
	question = "Please specify the length of cable to cut"
	ask_flags = ASK_INSIDE
	timeout = 0
	recheck_on_open = TRUE

/datum/prompt/number/mecha_cable_cut/present(mob/user)
	var/datum/tgui_input_number/prompt/box = new(user, question, title, default || 0, INFINITY, 0, timeout, TRUE, GLOB.tgui_always_state)
	rel_set(box, nameof(box.prompt), src)
	box.tgui_interact(user)
	return box

/datum/prompt/number/mecha_cable_cut/recheck_extra()
	var/mob/pilot = answerer
	if(!istype(pilot) || QDELETED(pilot))
		return "gone"
	if(subject && QDELETED(subject))
		return "gone"
	return null
