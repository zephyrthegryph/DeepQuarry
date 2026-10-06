/obj/machinery/suspension_gen
	maintenance_flags = MACHINE_MAINT_PANEL
	name = "suspension field generator"
	desc = "It has stubby bolts up against it's treads for stabilising. Used to hold anomalies stable in place."
	icon = 'icons/obj/xenoarchaeology.dmi'
	icon_state = "suspension"
	density = 1
	req_access = list(ACCESS_RESEARCH)
	var/obj/item/cell/cell
	var/tmp/obj/item/card/id/auth_card
	locked = 1
	var/power_use = 15

/// The field it projects while active (activate() .. deactivate()).
OM_FIELD_VIEW(/obj/machinery/suspension_gen, obj/effect/suspension_field, suspension_field, CHANGE_MACHINE_SETTINGS)

CAPABILITIES(/obj/machinery/suspension_gen)
	started_work(step = PROC_REF(work_step), starts = TRUE, when = nameof(suspension_field), wakes_on = list(nameof(suspension_field)))
	owns_one(nameof(suspension_field), /obj/effect/suspension_field)
	interface("XenoarchSuspension")
	without("ui_open")
	op("toggle_field", ui_act("toggle_field"), then(PROC_REF(ui_act_toggle_field)))
	op("lock", ui_act("lock"), then(PROC_REF(ui_act_lock)))
/// Holds its field (draining its cell) while it has one.
/obj/machinery/suspension_gen/Initialize(mapload)
	. = ..()
	make_rotatable()

/// Holds its field (draining its cell); runs while it has one (declared).
/obj/machinery/suspension_gen/proc/work_step(datum/act/timer/A)
	if(suspension_field)
		cell.charge -= power_use

		var/turf/T = get_turf(suspension_field)
		for(var/mob/living/M in turf_contents_of_type(T, /mob/living))
			M.status_at_least(STAT_WEAKENED, 3)
			cell.charge -= power_use
			if(prob(5))
				to_chat(M, span_warning("[pick("You feel tingly","You feel like floating","It is hard to speak","You can barely move")]."))

		for(var/obj/item/I in turf_contents_of_type(T, /obj/item))
			if(!contents_count(suspension_field))
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
		cell.forceMove(loc)
		cell.add_fingerprint(user)
		cell.update_icon()

		icon_state = "suspension"
		own_take(src, nameof(cell))
		to_chat(user, span_info("You remove the power cell"))
	return TRUE

/obj/machinery/suspension_gen/ui_data(datum/act/eval/A)
	var/list/data = list()
	data["cell"] = cell
	data["suspension_field"] = suspension_field
	var/list/merged_1 = ui_data_obj_machinery_suspension_gen(A.actor, null, null)
	if(islist(merged_1))
		for(var/merged_key_1 in merged_1)
			data[merged_key_1] = merged_1[merged_key_1]
	return data

/// /obj/machinery/suspension_gen's window data.
/obj/machinery/suspension_gen/proc/ui_data_obj_machinery_suspension_gen(mob/user, datum/tgui/ui, datum/tgui_state/state)
	var/list/data = list()

	data["cellCharge"] = cell?.charge
	data["cellMaxCharge"] = cell?.maxcharge

	data["locked"] = locked

	return data

/obj/machinery/suspension_gen/proc/ui_act_toggle_field(datum/act/op/A)
	var/mob/user = A.actor
	if(locked)
		return
	if(!suspension_field)
		if(cell.charge > 0)
			if(anchored)
				activate()
			else
				to_chat(user, span_warning("You are unable to activate [src] until it is properly secured on the ground."))
	else
		deactivate()
	return TRUE

/obj/machinery/suspension_gen/proc/ui_act_lock(datum/act/op/A)
	var/mob/user = A.actor
	if(allowed(user))
		set_locked(!locked)
		return TRUE

/obj/machinery/suspension_gen/screwdriver_act(mob/user, obj/item/tool)
	if(locked || suspension_field)
		return ITEM_INTERACT_BLOCKING
	return ..()

/obj/machinery/suspension_gen/wrench_act(mob/user, obj/item/tool)
	if(suspension_field)
		return ITEM_INTERACT_BLOCKING
	set_anchored(!anchored)
	playsound(src, tool.usesound, 50, TRUE)
	to_chat(user, span_info("You wrench the stabilising bolts [anchored ? "into place" : "loose"]."))
	if(anchored)
		desc = "Its tracks are held firmly in place with securing bolts."
		icon_state = "suspension_wrenched"
	else
		desc = "It has stubby bolts aligned along its tracks for stabilising."
		icon_state = "suspension"
	play_sfx(loc, SFX_ITEMS_RATCHET, 0.8, vary = FALSE)
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
			if(!move_into(src, nameof(src.cell), W, user))
				return TRUE
			to_chat(user, span_info("You insert the power cell."))
			icon_state = "suspension"
	return TRUE

/datum/interaction/machine_item/suspension_gen_swipe_card
	id = "suspension_gen_swipe_card"
	name = "Swipe card"
	held_type = /obj/item/card
	effect = /obj/machinery/suspension_gen/proc/interaction_swipe_card

/obj/machinery/suspension_gen/proc/interaction_swipe_card(mob/user, obj/item/card/I, datum/interaction/interaction)
	if(!auth_card())
		if(attempt_unlock(I, user))
			to_chat(user, span_info("You swipe [I], the console flashes \'<i>Access granted.</i>\'"))
		else
			to_chat(user, span_warning("You swipe [I], console flashes \'<i>Access denied.</i>\'"))
	else
		to_chat(user, span_warning("Remove [auth_card()] first."))
	return TRUE

/obj/machinery/suspension_gen/proc/attempt_unlock(obj/item/card/C, mob/user)
	if(!panel_open)
		if(istype(C, /obj/item/card/emag))
			C.resolve_attackby(src, user)
		else if(istype(C, /obj/item/card/id) && check_access(C))
			set_locked(0)
		if(!locked)
			return 1

DECLARE_EMAG_REPEATABLE(/obj/machinery/suspension_gen, PROC_REF(on_emag), null)
/obj/machinery/suspension_gen/proc/on_emag(remaining_charges, mob/user, obj/item/emag_source)
	if(cell && cell.charge > 0 && locked)
		set_locked(0)
		return 1

//checks for whether the machine can be activated or not should already have occurred by this point
/obj/machinery/suspension_gen/proc/activate()
	var/turf/T = get_turf(get_step(src,dir))
	var/collected = 0

	for(var/mob/living/M in turf_contents_of_type(T, /mob/living))
		M.status_at_least(STAT_WEAKENED, 5)
		act_message(M, null, MSG_SELF("You feel tingly and light, but it is difficult to move."), \
			MSG_OTHERS(span_blue("[icon2html(M,viewers(M))] %U% begins to float in the air!")))

	for(var/obj/effect/anomaly/anom in turf_contents_of_type(T, /obj/effect/anomaly))
		anom.immortal = TRUE
		anom.move_chance = 0
		if(!anom.stats)
			rel_set(anom, nameof(anom.stats), new /datum/anomaly_stats(anom))

	rel_set(src, nameof(suspension_field), new /obj/effect/suspension_field(T))
	visible_message(span_blue("[icon2html(src,viewers(src))] [src] activates with a low hum."))
	icon_state = "suspension_on"
	play_sfx(loc, SFX_MACHINES_QUIET_BEEP)
	update_icon()

	for(var/obj/item/I in turf_contents_of_type(T, /obj/item))
		I.forceMove(suspension_field)
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

	for(var/mob/living/M in turf_contents_of_type(T, /mob/living))
		to_chat(M, span_info("You no longer feel like floating."))
		M.status_at_least(STAT_WEAKENED, 3)

	for(var/obj/effect/anomaly/anom in turf_contents_of_type(T, /obj/effect/anomaly))
		if(anom.stats)
			var/datum/anomaly_stats/anom_stats = anom.stats
			if(istype(anom_stats.modifier, /datum/anomaly_modifiers/move))
				anom.move_chance = initial(anom.move_chance)
			continue
		else
			anom.move_chance = initial(anom.move_chance)

	visible_message(span_blue("[icon2html(src,viewers(src))] [src] deactivates with a gentle shudder."))
	own_clear(src, nameof(suspension_field), OWN_DELETE)
	icon_state = "suspension_wrenched"
	play_sfx(loc, SFX_MACHINES_QUIET_BEEP)
	update_icon()

// its field deactivates.
/obj/machinery/suspension_gen/on_destroy(force)
	deactivate()
	..()

DECLARE_APPEARANCE_PROC(/obj/machinery/suspension_gen, TYPE_PROC_REF(/atom, appearance_overlays), list())
/obj/machinery/suspension_gen/appearance_overlays()
	. = list()
	if(panel_open)
		. += "suspension_panel"
	. += ..()

/obj/effect/suspension_field
	name = "energy field"
	icon = 'icons/effects/effects.dmi'
	anchored = 1
	density = 1

CAPABILITIES(/obj/effect/suspension_field)
	owns_many(nameof(contents), on_destroy = ON_DESTROY_SPILL)


/obj/machinery/suspension_gen/ownership()
	. = ..()
	. += owns(nameof(cell), policy = OWN_CONTAINED, starts = /obj/item/cell/high)

/// Accessor for the auth_card var.
/obj/machinery/suspension_gen/proc/auth_card() as /obj/item/card/id
	return auth_card
