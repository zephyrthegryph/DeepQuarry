/obj/machinery/suspension_gen
	maintenance_flags = MACHINE_MAINT_PANEL
	name = "suspension field generator"
	desc = "It has stubby bolts up against it's treads for stabilising. Used to hold anomalies stable in place."
	icon = 'icons/obj/xenoarchaeology.dmi'
	icon_state = "suspension"
	density = 1
	req_access = list(ACCESS_RESEARCH)
	var/obj/item/cell/cell
	var/obj/item/card/id/auth_card
	var/locked = 1
	var/power_use = 15
	var/obj/effect/suspension_field/suspension_field

/obj/machinery/suspension_gen/Initialize(mapload)
	. = ..()
	cell = new /obj/item/cell/high(src)
	AddElement(/datum/element/rotatable)

/obj/machinery/suspension_gen/process()
	if(suspension_field)
		cell.charge -= power_use

		var/turf/T = get_turf(suspension_field)
		for(var/mob/living/M in T)
			M.Weaken(3)
			cell.charge -= power_use
			if(prob(5))
				to_chat(M, span_warning("[pick("You feel tingly","You feel like floating","It is hard to speak","You can barely move")]."))

		for(var/obj/item/I in T)
			if(!suspension_field.contents.len)
				suspension_field.icon_state = "energynet"
				suspension_field.add_overlay("shield2")
			I.forceMove(suspension_field)

		if(cell.charge <= 0)
			deactivate()

/obj/machinery/suspension_gen/declare_interactions(list/into)
	into += list(
		/datum/interaction/machine_item/suspension_gen_insert_cell,
		/datum/interaction/machine_item/suspension_gen_swipe_card,
		/datum/interaction/machine_hand/ungated/suspension_gen_use,
	)
	..()

/datum/interaction/machine_hand/ungated/suspension_gen_use
	id = "suspension_gen_use"
	name = "Use"
	effect = /obj/machinery/suspension_gen/proc/interaction_use

/obj/machinery/suspension_gen/proc/interaction_use(mob/user, obj/item/held, datum/interaction/interaction)
	if(!panel_open)
		tgui_interact(user)
	else if(cell)
		cell.loc = loc
		cell.add_fingerprint(user)
		cell.update_icon()

		icon_state = "suspension"
		cell = null
		to_chat(user, span_info("You remove the power cell"))
	return TRUE

/obj/machinery/suspension_gen/tgui_interact(mob/user, datum/tgui/ui)
	ui = SStgui.try_update_ui(user, src, ui)
	if(!ui)
		ui = new(user, src, "XenoarchSuspension", name)
		ui.open()

/obj/machinery/suspension_gen/tgui_data(mob/user, datum/tgui/ui, datum/tgui_state/state)
	var/list/data = ..()

	data["cell"] = cell
	data["cellCharge"] = cell?.charge
	data["cellMaxCharge"] = cell?.maxcharge

	data["locked"] = locked
	data["suspension_field"] = suspension_field

	return data

/obj/machinery/suspension_gen/tgui_act(action, list/params, datum/tgui/ui, datum/tgui_state/state)
	if(..())
		return TRUE

	switch(action)
		if("toggle_field")
			if(locked)
				return
			if(!suspension_field)
				if(cell.charge > 0)
					if(anchored)
						activate()
					else
						to_chat(ui.user, span_warning("You are unable to activate [src] until it is properly secured on the ground."))
			else
				deactivate()
			return TRUE

		if("lock")
			if(allowed(ui.user))
				locked = !locked
				return TRUE

/obj/machinery/suspension_gen/screwdriver_act(mob/user, obj/item/tool)
	if(locked || suspension_field)
		return ITEM_INTERACT_BLOCKING
	return ..()

/obj/machinery/suspension_gen/wrench_act(mob/user, obj/item/tool)
	if(suspension_field)
		return ITEM_INTERACT_BLOCKING
	anchored = !anchored
	playsound(src, tool.usesound, 50, TRUE)
	to_chat(user, span_info("You wrench the stabilising bolts [anchored ? "into place" : "loose"]."))
	if(anchored)
		desc = "Its tracks are held firmly in place with securing bolts."
		icon_state = "suspension_wrenched"
	else
		desc = "It has stubby bolts aligned along its tracks for stabilising."
		icon_state = "suspension"
	playsound(loc, 'sound/items/Ratchet.ogg', 40)
	update_icon()
	return ITEM_INTERACT_SUCCESS

/datum/interaction/machine_item/suspension_gen_insert_cell
	id = "suspension_gen_insert_cell"
	name = "Insert power cell"
	held_type = /obj/item/cell
	effect = /obj/machinery/suspension_gen/proc/interaction_insert_cell

/obj/machinery/suspension_gen/proc/interaction_insert_cell(mob/user, obj/item/W, datum/interaction/interaction)
	if(panel_open)
		if(cell)
			to_chat(user, span_warning("There is a power cell already installed."))
		else
			user.drop_item()
			W.loc = src
			cell = W
			to_chat(user, span_info("You insert the power cell."))
			icon_state = "suspension"
	return TRUE

/datum/interaction/machine_item/suspension_gen_swipe_card
	id = "suspension_gen_swipe_card"
	name = "Swipe card"
	held_type = /obj/item/card
	effect = /obj/machinery/suspension_gen/proc/interaction_swipe_card

/obj/machinery/suspension_gen/proc/interaction_swipe_card(mob/user, obj/item/card/I, datum/interaction/interaction)
	if(!auth_card)
		if(attempt_unlock(I, user))
			to_chat(user, span_info("You swipe [I], the console flashes \'<i>Access granted.</i>\'"))
		else
			to_chat(user, span_warning("You swipe [I], console flashes \'<i>Access denied.</i>\'"))
	else
		to_chat(user, span_warning("Remove [auth_card] first."))
	return TRUE

/obj/machinery/suspension_gen/proc/attempt_unlock(obj/item/card/C, mob/user)
	if(!panel_open)
		if(istype(C, /obj/item/card/emag))
			C.resolve_attackby(src, user)
		else if(istype(C, /obj/item/card/id) && check_access(C))
			locked = 0
		if(!locked)
			return 1

/obj/machinery/suspension_gen/emag_act(remaining_charges, mob/user)
	if(cell && cell.charge > 0 && locked)
		locked = 0
		return 1

//checks for whether the machine can be activated or not should already have occurred by this point
/obj/machinery/suspension_gen/proc/activate()
	var/turf/T = get_turf(get_step(src,dir))
	var/collected = 0

	for(var/mob/living/M in T)
		M.Weaken(5)
		M.visible_message(span_blue("[icon2html(M,viewers(M))] [M] begins to float in the air!"),"You feel tingly and light, but it is difficult to move.")

	for(var/obj/effect/anomaly/anom in T)
		anom.immortal = TRUE
		anom.move_chance = 0
		if(!anom.stats)
			anom.stats = new /datum/anomaly_stats(anom)

	suspension_field = new(T)
	visible_message(span_blue("[icon2html(src,viewers(src))] [src] activates with a low hum."))
	icon_state = "suspension_on"
	playsound(loc, 'sound/machines/quiet_beep.ogg', 40)
	update_icon()

	for(var/obj/item/I in T)
		I.loc = suspension_field
		collected++

	if(collected)
		suspension_field.icon_state = "energynet"
		add_overlay("shield2")
		visible_message(span_blue("[icon2html(suspension_field,viewers(src))] [suspension_field] gently absconds [collected > 1 ? "something" : "several things"]."))
	else
		if(ismineralturf(T) || istype(T,/turf/simulated/wall))
			suspension_field.icon_state = "shieldsparkles"
		else
			suspension_field.icon_state = "shield2"

/obj/machinery/suspension_gen/proc/deactivate()
	//drop anything we picked up
	var/turf/T = get_turf(suspension_field)

	for(var/mob/living/M in T)
		to_chat(M, span_info("You no longer feel like floating."))
		M.Weaken(3)

	for(var/obj/effect/anomaly/anom in T)
		if(anom.stats)
			var/datum/anomaly_stats/anom_stats = anom.stats
			if(istype(anom_stats.modifier, /datum/anomaly_modifiers/move))
				anom.move_chance = initial(anom.move_chance)
			continue
		else
			anom.move_chance = initial(anom.move_chance)

	visible_message(span_blue("[icon2html(src,viewers(src))] [src] deactivates with a gentle shudder."))
	qdel(suspension_field)
	suspension_field = null
	icon_state = "suspension_wrenched"
	playsound(loc, 'sound/machines/quiet_beep.ogg', 40)
	update_icon()

/obj/machinery/suspension_gen/Destroy()
	deactivate()
	. = ..()

/obj/machinery/suspension_gen/update_icon()
	cut_overlays()
	if(panel_open)
		add_overlay("suspension_panel")
	else
		cut_overlay("suspension_panel")
	. = ..()

/obj/effect/suspension_field
	name = "energy field"
	icon = 'icons/effects/effects.dmi'
	anchored = 1
	density = 1

/obj/effect/suspension_field/Destroy()
	for(var/atom/movable/I in src)
		I.dropInto(loc)
	return ..()
