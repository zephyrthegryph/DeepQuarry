// Base type, do not use.
/obj/structure/lift
	resistance_flags = BOMB_PROOF
	name = "turbolift control component"
	icon = 'icons/obj/turbolift.dmi'
	anchored = TRUE
	density = FALSE
	plane = MOB_PLANE

	var/tmp/lift_handle

/obj/structure/lift/set_dir(newdir)
	. = ..()
	pixel_x = 0
	pixel_y = 0
	if(dir & NORTH)
		pixel_y = -32
	else if(dir & SOUTH)
		pixel_y = 32
	else if(dir & EAST)
		pixel_x = -32
	else if(dir & WEST)
		pixel_x = 32

/// `stance`: the touch's stance (a tgui button press is a plain press).
/obj/structure/lift/proc/pressed(mob/user, stance = I_HELP)
	if(!istype(user, /mob/living/silicon))
		if(stance == I_HURT)
			user.visible_message(span_danger("\The [user] hammers on the lift button!"))
		else
			user.visible_message(span_infoplain(span_bold("\The [user]") + " presses the lift button."))

/obj/structure/lift/Initialize(mapload, datum/turbolift/_lift)
	. = ..()
	lift_handle = om_handle(_lift)

/obj/structure/lift
	silicon_use = SILICON_USE_HAND

/obj/structure/lift/attack_generic(mob/user)
	return attack_hand(user)

DECLARE_INTERACTIONS(/obj/structure/lift, INTERACT_HAND_UNGATED_AS(I_HURT, "Hammer on it", PROC_REF(interaction_hand)), INTERACT_HAND_UNGATED(null, PROC_REF(interaction_hand)))

/// Old attack_hand.
/obj/structure/lift/proc/interaction_hand(mob/user, obj/item/held, datum/interaction/interaction)
	return interact(user, interaction.stance)

/// `stance`: the touch's stance, passed on to pressed().
/obj/structure/lift/interact(mob/user, stance = I_HELP)
	if(!lift().is_functional())
		return 0
	return 1
// End base.

// Button. No HTML interface, just calls the associated lift to its floor.
/obj/structure/lift/button
	name = "elevator button"
	desc = "A call button for an elevator. Be sure to hit it three hundred times."
	icon_state = "button"
	var/light_up = FALSE
	req_access = list(ACCESS_EVA)
	var/datum/turbolift_floor/floor

REL_PAIR(/obj/structure/lift/button, floor, ext_panel)
REL_PAIR(/datum/turbolift_floor, ext_panel, floor)

/obj/structure/lift/button/proc/reset()
	light_up = FALSE
	update_icon()

// Hit it with a PDA or ID to enable priority call mode
EXTEND_INTERACTIONS(/obj/structure/lift/button, INTERACT_ITEM(null, PROC_REF(interaction_item)))

/// Old attackby.
/obj/structure/lift/button/proc/interaction_item(mob/user, obj/item/W, datum/interaction/interaction)
	var/obj/item/card/id/id = W.GetID()
	if(istype(id))
		if(!check_access(id))
			playsound(src, 'sound/machines/buzz-two.ogg', 50, 0)
			return INTERACTION_HANDLED_PASS
		lift().priority_mode()
		if(floor == lift().current_floor())
			lift().open_doors()
		else
			lift().queue_move_to(floor)
		return INTERACTION_HANDLED_PASS
	return FALSE

/obj/structure/lift/button/interact(mob/user, stance = I_HELP)
	if(!..())
		return
	if(lift().fire_mode || lift().priority_mode)
		playsound(src, 'sound/machines/buzz-two.ogg', 50, 0)
		return
	light_up()
	pressed(user, stance)
	if(floor == lift().current_floor() && !(lift().target_floor()))	//Make sure we're not going anywhere before opening doors
		lift().open_doors()
		om_after(src, 3, PROC_REF(reset))
		return
	lift().queue_move_to(floor)

/obj/structure/lift/button/allow_pai_interaction(mob/living/silicon/pai/user, proximity_flag)
	return proximity_flag

/obj/structure/lift/button/proc/light_up()
	light_up = TRUE
	update_icon()

/obj/structure/lift/button/update_icon()
	if(lift().fire_mode)
		icon_state = "button_fire"
	else if(lift().priority_mode)
		icon_state = "button_pri"
	else if(light_up)
		icon_state = "button_lit"
	else
		icon_state = initial(icon_state)

// End button.

// Panel. Lists floors (HTML), moves with the elevator, schedules a move to a given floor.
/obj/structure/lift/panel
	name = "elevator control panel"
	desc = "A control panel for moving the elevator. There's a slot for swiping IDs to enable additional controls."
	icon_state = "panel"
	req_access = list(ACCESS_EVA)
	req_one_access = list(ACCESS_HEADS, ACCESS_ATMOSPHERICS, ACCESS_MEDICAL)

// Hit it with a PDA or ID to enable priority call mode
EXTEND_INTERACTIONS(/obj/structure/lift/panel, \
	INTERACT_ITEM(null, PROC_REF(interaction_item)), \
	INTERACT_OBSERVER("View", TYPE_PROC_REF(/atom, interaction_interact)), \
)

/// Old attackby.
/obj/structure/lift/panel/proc/interaction_item(mob/user, obj/item/W, datum/interaction/interaction)
	var/obj/item/card/id/id = W.GetID()
	if(istype(id))
		if(!check_access(id))
			playsound(src, 'sound/machines/buzz-two.ogg', 50, 0)
			return INTERACTION_HANDLED_PASS
		lift().update_fire_mode(!lift().fire_mode)
		if(lift().fire_mode)
			audible_message(span_danger("Firefighter Mode Activated.  Door safeties disabled.  Manual control engaged."), runemessage = "SCREECH")
			playsound(src, 'sound/machines/airalarm.ogg', 25, 0, 4, volume_channel = VOLUME_CHANNEL_ALARMS)
		else
			audible_message(span_warning("Firefighter Mode Deactivated. Door safeties enabled.  Automatic control engaged."), runemessage = "ding")
		return INTERACTION_HANDLED_PASS
	return FALSE

/obj/structure/lift/panel/allow_pai_interaction(mob/living/silicon/pai/user, proximity_flag)
	return proximity_flag

/obj/structure/lift/panel/interact(mob/user)
	if(!..())
		return

	tgui_interact(user)

/obj/structure/lift/panel/tgui_interact(mob/user, datum/tgui/ui)
	ui = SStgui.try_update_ui(user, src, ui)
	if(!ui)
		ui = new(user, src, "Turbolift", name)
		ui.open()

/obj/structure/lift/panel/tgui_data(mob/user)
	var/list/data = list()

	data["doors_open"] = lift().doors_are_open()
	data["fire_mode"] = lift().fire_mode

	var/list/floors = list()
	for(var/i in lift().floors.len to 1 step -1)
		var/datum/turbolift_floor/floor = lift().floors[i]
		floors.Add(list(list(
			"id" = i,
			"ref" = "\ref[floor]",
			"queued" = (floor in lift().queued_floors),
			"target" = (lift().target_floor() == floor),
			"current" = (lift().current_floor() == floor),
			"label" = floor.label,
			"name" = floor.name,
		)))
	data["floors"] = floors

	return data

/obj/structure/lift/panel/tgui_act(action, params, datum/tgui/ui)
	if(..())
		return TRUE

	switch(action)
		if("move_to_floor")
			. = TRUE
			lift().queue_move_to(locate(params["ref"]))
		if("toggle_doors")
			. = TRUE
			if(lift().doors_are_open())
				lift().close_doors()
			else
				lift().open_doors()
		if("emergency_stop")
			. = TRUE
			lift().emergency_stop()

	if(.)
		pressed(ui.user)

/obj/structure/lift/panel/update_icon()
	if(lift().fire_mode)
		icon_state = "panel_fire"
	else
		icon_state = initial(icon_state)

// End panel.

/// LC-refs: the lift this refers to -- an OM handle (om_handle()), so it reads null once that is deleted.
/obj/structure/lift/proc/lift() as /datum/turbolift
	return om_resolve(lift_handle)
